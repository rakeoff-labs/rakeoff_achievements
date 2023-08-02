import IcpLedgerInterface "./ledger_interface/ledger";
import GovernanceInterface "./governance_interface/governance";
import IcpAccountTools "./ledger_interface/account";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Hex "mo:encoding/Hex";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Text "mo:base/Text";
import Iter "mo:base/Iter";

// Welcome to the RakeoffAchievements smart contract
// This smart contract must be made HotKey to fetch neurons data.
// A hotkey has access to a neurons full data.
// A hotkey can only vote, make proposals and change the following of a neuron.

shared ({ caller = owner }) actor class RakeoffAchievements() = thisCanister {

  /////////////////
  // Constants ////
  /////////////////

  // ICP ledger canister
  let IcpLedger = actor "ryjl3-tyaaa-aaaaa-aaaba-cai" : IcpLedgerInterface.Self;

  // ICP governance canister
  let Governance = actor "rrkah-fqaaa-aaaaa-aaaaq-cai" : GovernanceInterface.Self;

  // The standard ICP transaction fee
  let ICP_PROTOCOL_FEE : Nat64 = 10_000;

  // Achievement levels
  let LEVEL_1 : AchievementLevel = {
    level_id = 1;
    icp_amount_needed = 100000000; // 1 ICP
    icp_reward = 100000000; // 1 ICP
  };

  let LEVEL_2 : AchievementLevel = {
    level_id = 2;
    icp_amount_needed = 1000000000; // 10 ICP
    icp_reward = 100000000; // 1 ICP
  };

  let LEVEL_3 : AchievementLevel = {
    level_id = 3;
    icp_amount_needed = 10000000000; // 100 ICP
    icp_reward = 100000000; // 1 ICP
  };

  /////////////
  // Types ////
  /////////////

  public type AchievementLevel = {
    level_id : Nat;
    icp_amount_needed : Nat64;
    icp_reward : Nat64;
  };

  public type CanisterAccount = {
    icp_address : Text;
    icp_balance : Nat64;
    icp_claimed : Nat64;
  };

  public type NeuronAcheivementLevel = {
    neuron_id : Nat64;
    current_level : AchievementLevel;
    cached_level : ?AchievementLevel; // checks the canister state
    reward_is_due : Bool;
    reward_amount_due : Nat64;
    canister_rewards_available : Bool;
  };

  //////////////////////
  // Canister State ////
  //////////////////////

  private stable var _icpClaimed : Nat64 = 0;

  private func nat64Hash(x : Nat64) : Hash.Hash {
    Text.hash(Nat64.toText(x));
  };

  private var _neuronAchievementLevel = HashMap.HashMap<Nat64, AchievementLevel>(
    10,
    Nat64.equal,
    nat64Hash,
  );

  // Maintain hashmap state
  private stable var _neuronLevelStorage : [(Nat64, AchievementLevel)] = [];

  system func preupgrade() {
    _neuronLevelStorage := Iter.toArray(_neuronAchievementLevel.entries());
  };

  system func postupgrade() {
    _neuronAchievementLevel := HashMap.fromIter(
      Iter.fromArray(_neuronLevelStorage),
      _neuronLevelStorage.size(),
      Nat64.equal,
      nat64Hash,
    );
  };

  ////////////////////////
  // Public Functions ////
  ////////////////////////

  public shared ({ caller }) func get_canister_accounts() : async Result.Result<CanisterAccount, Text> {
    assert (caller == owner);
    return await getCanisterAccounts(caller);
  };

  public shared ({ caller }) func check_achievement_level_reward(neuronId : Nat64) : async Result.Result<NeuronAcheivementLevel, Text> {
    assert (Principal.isAnonymous(caller) == false);
    return await checkAcheivementLevelReward(neuronId);
  };

  public shared ({ caller }) func claim_achievement_level_reward(neuronId : Nat64) : async Result.Result<Text, Text> {
    assert (Principal.isAnonymous(caller) == false);
    return await claimAchievementLevelReward(caller, neuronId);
  };

  ////////////////////////////////////
  // Private Achievement Functions ///
  ////////////////////////////////////

  private func checkAcheivementLevelReward(neuronId : Nat64) : async Result.Result<NeuronAcheivementLevel, Text> {
    let neuronDataResult = await Governance.get_neuron_info(neuronId);
    let canisterIcpBalance = await getCanisterIcpBalance();

    switch (neuronDataResult) {
      case (#Ok neuronData) {
        let oldLevel = _neuronAchievementLevel.get(neuronId);
        let newLevel = verifyNeuronAchievementLevel(neuronData.stake_e8s);
        let rewardsDue = verifyIcpRewardsDue(oldLevel, newLevel);

        return #ok({
          neuron_id = neuronId;
          current_level = newLevel;
          cached_level = oldLevel;
          reward_is_due = rewardsDue > 0;
          reward_amount_due = rewardsDue;
          canister_rewards_available = canisterIcpBalance > (rewardsDue + ICP_PROTOCOL_FEE);
        });
      };
      case (#Err result) {
        return #err("Could not fetch neuron data");
      };
    };
  };

  // For this to work this canister must be made a hotkey
  private func claimAchievementLevelReward(caller : Principal, neuronId : Nat64) : async Result.Result<Text, Text> {
    let neuronDataResult = await Governance.get_full_neuron(neuronId);
    let canisterIcpBalance = await getCanisterIcpBalance();

    switch (neuronDataResult) {
      case (#Ok neuronData) {
        let isOwner = verifyCallerOwnsNeuron(caller, neuronData.controller);
        if (not isOwner) {
          return #err("Caller does not own this neuron");
        };

        let isStaking = verifyNeuronIsStaking(neuronData.dissolve_state);
        if (not isStaking) {
          return #err("Neuron needs to be locked and hit minimum lockup threshold");
        };

        let oldLevel = _neuronAchievementLevel.get(neuronId);
        let newLevel = verifyNeuronAchievementLevel(neuronData.cached_neuron_stake_e8s);

        let rewardsDue = verifyIcpRewardsDue(oldLevel, newLevel);

        if (rewardsDue <= 0) {
          return #err("Neuron is not due any rewards");
        };

        if (canisterIcpBalance <= (rewardsDue + ICP_PROTOCOL_FEE)) {
          return #err("Canister has insufficient funds");
        };

        let transferResult = await canisterTransferIcp(neuronData.account, (rewardsDue + ICP_PROTOCOL_FEE));
        switch (transferResult) {
          case (#Ok result) {
            _neuronAchievementLevel.put(neuronId, newLevel);
            _icpClaimed += (rewardsDue + ICP_PROTOCOL_FEE);
            return #ok("Reward successfully disbursed");
          };
          case (#Err result) {
            return #err("Failed to transfer rewards, please try again");
          };
        };
      };
      case (#Err result) {
        return #err("Please ensure the canister is added as hotkey");
      };
    };
  };

  ////////////////////////////////////
  // Private Verification Functions ///
  ////////////////////////////////////

  private func verifyCallerOwnsNeuron(caller : Principal, neuronController : ?Principal) : Bool {
    switch (neuronController) {
      case (?controller) {
        return Principal.equal(controller, caller);
      };
      case (null) {
        return false;
      };
    };
  };

  private func verifyNeuronAchievementLevel(neuronStake : Nat64) : AchievementLevel {
    if (neuronStake >= LEVEL_3.icp_amount_needed) {
      return LEVEL_3;
    } else if (neuronStake >= LEVEL_2.icp_amount_needed) {
      return LEVEL_2;
    } else {
      return LEVEL_1; // always atleast level 1
    };
  };

  private func verifyIcpRewardsDue(oldLevel : ?AchievementLevel, newLevel : AchievementLevel) : Nat64 {
    switch (oldLevel) {
      case (?old) {
        switch ((old.level_id, newLevel.level_id)) {
          case (2, 3) { return LEVEL_3.icp_reward };
          case (1, 2) { return LEVEL_2.icp_reward };
          case (1, 3) { return LEVEL_2.icp_reward + LEVEL_3.icp_reward }; // Direct transition from 1 to 3
          case _ { return 0 }; // All other transitions
        };
      };
      case (null) {
        // no previous level
        switch (newLevel.level_id) {
          case 3 {
            return LEVEL_1.icp_reward + LEVEL_2.icp_reward + LEVEL_3.icp_reward;
          };
          case 2 { return LEVEL_1.icp_reward + LEVEL_2.icp_reward };
          case _ { return LEVEL_1.icp_reward }; // minimum level 1 reward
        };
      };
    };
  };

  private func verifyNeuronIsStaking(dissolveState : ?GovernanceInterface.DissolveState) : Bool {
    let minimumSecondsNeeded : Nat64 = 15_813_200; // minimum of 6 months

    switch (dissolveState) {
      case (? #DissolveDelaySeconds(value)) {
        return value >= minimumSecondsNeeded;
      };
      case (? #WhenDissolvedTimestampSeconds(_)) {
        return false;
      };
      case null {
        return false;
      };
    };
  };

  ///////////////////////////////////
  // Private ICP wallet Functions ///
  ///////////////////////////////////

  private func getCanisterIcpAddress() : [Nat8] {
    let ownerAccount = Principal.fromActor(thisCanister);
    let subAccount = IcpAccountTools.defaultSubaccount();

    return Blob.toArray(IcpAccountTools.accountIdentifier(ownerAccount, subAccount));
  };

  private func getCanisterIcpBalance() : async Nat64 {
    let balance = await IcpLedger.account_balance({
      account = getCanisterIcpAddress();
    });

    return balance.e8s;
  };

  private func getCanisterAccounts(caller : Principal) : async Result.Result<CanisterAccount, Text> {
    let canisterIcpBalance = await getCanisterIcpBalance();

    return #ok({
      icp_address = Hex.encode(getCanisterIcpAddress());
      icp_balance = canisterIcpBalance;
      icp_claimed = _icpClaimed;
    });
  };

  private func canisterTransferIcp(transfer_to : [Nat8], transfer_amount : Nat64) : async IcpLedgerInterface.TransferResult {
    return await IcpLedger.transfer({
      memo : Nat64 = 0;
      from_subaccount = ?Blob.toArray(IcpAccountTools.defaultSubaccount());
      to = transfer_to;
      amount = { e8s = transfer_amount - ICP_PROTOCOL_FEE };
      fee = { e8s = ICP_PROTOCOL_FEE };
      created_at_time = ?{
        timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
      };
    });
  };
};
