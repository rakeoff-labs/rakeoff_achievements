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

  public shared ({ caller }) func testing(neuronId : Nat64) : async Result.Result<Text, Text> {
    return await claimAchievementLevelReward(caller, neuronId);
  };

  ////////////////////////////////////
  // Private Achievement Functions ///
  ////////////////////////////////////

  // TODO
  // need a quick query call function to check if NeuronID in hashmap also to check the level in the hashmap and see if the nueron is due a reward from a new level, this is for the UI (IE reward available)

  private func claimAchievementLevelReward(caller : Principal, neuronId : Nat64) : async Result.Result<Text, Text> {
    let neuronDataResult = await Governance.get_full_neuron(neuronId);

    switch (neuronDataResult) {
      case (#Ok neuronData) {
        let isOwner = verifyCallerOwnsNeuron(caller, neuronData);
        if (not isOwner) {
          return #err("Caller does not own this neuron");
        };

        let isStaking = verifyNeuronIsStaking(neuronData);
        if (not isStaking) {
          return #err("Neuron needs to be locked and hit minimum lockup threshold");
        };

        let oldLevel = _neuronAchievementLevel.get(neuronId);
        let newLevel = verifyNeuronAchievementLevel(neuronData);

        let rewardsDue = verifyIcpRewardsDue(oldLevel, newLevel);

        if (rewardsDue > 0) {
          let transferResult = await canisterTransferIcp(neuronData.account, rewardsDue);
          switch (transferResult) {
            case (#Ok result) {
              _neuronAchievementLevel.put(neuronId, newLevel);
              return #ok("Reward successfully disbursed");
            };
            case (#Err result) {
              #err("Failed to transfer rewards, please try again");
            };
          };
        } else {
          return #err("Neuron is not due any rewards");
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

  private func verifyCallerOwnsNeuron(caller : Principal, neuronData : GovernanceInterface.Neuron) : Bool {
    switch (neuronData.controller) {
      case (?controller) {
        return Principal.equal(controller, caller);
      };
      case (null) {
        return false;
      };
    };
  };

  private func verifyNeuronAchievementLevel(neuronData : GovernanceInterface.Neuron) : AchievementLevel {
    if (neuronData.cached_neuron_stake_e8s >= LEVEL_3.icp_amount_needed) {
      return LEVEL_3;
    } else if (neuronData.cached_neuron_stake_e8s >= LEVEL_2.icp_amount_needed) {
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

  private func verifyNeuronIsStaking(neuronData : GovernanceInterface.Neuron) : Bool {
    let dissolveState = neuronData.dissolve_state;
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
