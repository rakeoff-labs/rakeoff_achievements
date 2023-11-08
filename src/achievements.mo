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
import Option "mo:base/Option";

// Welcome to the RakeoffAchievements smart contract.
// This smart contract must be made HotKey to disburse an achievement reward.
// A hotkey can ONLY fetch data, vote, make proposals and change the following of a neuron.

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

  // ICP values are denominated in e8s, so 1 ICP is 100,000,000 e8s
  let TOTAL_ICP_REWARD : Nat64 = 100_000_000; // 1 ICP

  // Achievement levels
  let LEVEL_1 : AchievementLevel = {
    level_id = 1;
    icp_amount_needed = 100_000_000; // 1 ICP
    icp_reward = TOTAL_ICP_REWARD / 20; // 0.05 ICP
  };

  let LEVEL_2 : AchievementLevel = {
    level_id = 2;
    icp_amount_needed = 1_000_000_000; // 10 ICP
    icp_reward = TOTAL_ICP_REWARD / 10; // 0.1 ICP
  };

  let LEVEL_3 : AchievementLevel = {
    level_id = 3;
    icp_amount_needed = 2_500_000_000; // 25 ICP
    icp_reward = TOTAL_ICP_REWARD / 10; // 0.1 ICP
  };

  let LEVEL_4 : AchievementLevel = {
    level_id = 4;
    icp_amount_needed = 5_000_000_000; // 50 ICP
    icp_reward = TOTAL_ICP_REWARD / 4; // 0.25 ICP
  };

  let LEVEL_5 : AchievementLevel = {
    level_id = 5;
    icp_amount_needed = 10_000_000_000; // 100 ICP
    icp_reward = TOTAL_ICP_REWARD / 2; // 0.5 ICP
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
  };

  public type CanisterStats = {
    icp_claimed : Nat64;
    ongoing_transfers : [(Principal, Nat64)];
    total_neurons_added : Nat;
  };

  public type NeuronCheckResults = {
    two_weeks_old : Bool;
    is_staking : Bool;
    is_locked_for_6_months : Bool;
    new_achievement_reward_due : Bool;
  };

  public type NeuronAchievementDetails = {
    neuron_id : Nat64;
    current_level : AchievementLevel;
    cached_level : ?AchievementLevel; // checks the canister state
    neuron_passes_checks : Bool;
    neuron_checks : NeuronCheckResults;
    reward_amount_due : Nat64;
  };

  public type NeuronCheckArgs = {
    neuronId : Nat64;
    stake_e8s : Nat64;
    age_seconds : Nat64;
    state : Int32;
    dissolve_delay_seconds : Nat64;
  };

  //////////////////////
  // Canister State ////
  //////////////////////

  private stable var _TotalIcpClaimed : Nat64 = 0;

  // temporary memory - to avoid double spend attack
  private var _ongoingRewardTransfers = HashMap.HashMap<Principal, Nat64>(10, Principal.equal, Principal.hash);

  private func nat64Hash(x : Nat64) : Hash.Hash {
    Text.hash(Nat64.toText(x));
  };

  // stable storage to track the neurons achievements levels
  private var _neuronAchievementLevel = HashMap.HashMap<Nat64, AchievementLevel>(10, Nat64.equal, nat64Hash);

  // Maintain stable hashmap state
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

  public shared ({ caller }) func get_canister_account() : async Result.Result<CanisterAccount, Text> {
    assert (caller == owner);
    return await getCanisterAccount(caller);
  };

  public query func get_canister_stats() : async Result.Result<CanisterStats, Text> {
    return getCanisterStats();
  };

  public shared query ({ caller }) func check_achievement_level_reward(neuronCheckArgs : NeuronCheckArgs) : async Result.Result<NeuronAchievementDetails, Text> {
    assert (Principal.isAnonymous(caller) == false);
    return checkAcheivementLevelReward(neuronCheckArgs);
  };

  public shared ({ caller }) func claim_achievement_level_reward(neuronId : Nat64) : async Result.Result<Text, Text> {
    assert (Principal.isAnonymous(caller) == false);
    return await claimAchievementLevelReward(caller, neuronId);
  };

  public shared query ({ caller }) func show_available_levels() : async [AchievementLevel] {
    assert (Principal.isAnonymous(caller) == false);
    return [LEVEL_1, LEVEL_2, LEVEL_3, LEVEL_4, LEVEL_5];
  };

  ////////////////////////////////////
  // Private Achievement Functions ///
  ////////////////////////////////////

  // A query call function to quickly check a neurons achievement level - you must know the details of the neuron submitted
  private func checkAcheivementLevelReward(neuronCheckArgs : NeuronCheckArgs) : Result.Result<NeuronAchievementDetails, Text> {
    let oldLevel = _neuronAchievementLevel.get(neuronCheckArgs.neuronId);
    let newLevel = verifyNeuronAchievementLevel(neuronCheckArgs.stake_e8s);

    return #ok({
      neuron_id = neuronCheckArgs.neuronId;
      current_level = newLevel;
      cached_level = oldLevel;
      neuron_passes_checks = verifyNeuronAge(neuronCheckArgs.age_seconds) and verifyNeuronIsStaking(neuronCheckArgs.state, neuronCheckArgs.dissolve_delay_seconds) and (verifyIcpRewardsDue(oldLevel, newLevel) > 0);
      neuron_checks = {
        two_weeks_old = verifyNeuronAge(neuronCheckArgs.age_seconds);
        is_staking = neuronCheckArgs.state == 1;
        is_locked_for_6_months = verifyNeuronIsStaking(neuronCheckArgs.state, neuronCheckArgs.dissolve_delay_seconds);
        new_achievement_reward_due = (verifyIcpRewardsDue(oldLevel, newLevel) > 0);
      };
      reward_amount_due = verifyIcpRewardsDue(oldLevel, newLevel);
    });
  };

  private func claimAchievementLevelReward(caller : Principal, neuronId : Nat64) : async Result.Result<Text, Text> {
    // initiate message 1 to fetch neuron data
    let neuronDataResult = await Governance.list_neurons({
      neuron_ids = [neuronId];
      include_neurons_readable_by_caller = false;
    });

    // initiate message 2
    if (neuronDataResult.neuron_infos.size() == 0) {
      return #err("No neuron info available for the given neuron ID");
    };

    if (neuronDataResult.full_neurons.size() == 0) {
      return #err("No full neuron info available. Please ensure the canister is hotkey");
    };

    let neuronInfo = neuronDataResult.neuron_infos[0].1;
    let neuronFullInfo = neuronDataResult.full_neurons[0];

    // perform our validations
    if (not verifyCallerOwnsNeuron(caller, neuronFullInfo.controller)) {
      return #err("Caller does not own this neuron");
    };

    if (not verifyNeuronIsStaking(neuronInfo.state, neuronInfo.dissolve_delay_seconds)) {
      return #err("Neuron needs to be locked and hit the minimum dissolve delay threshold");
    };

    if (not verifyNeuronAge(neuronInfo.age_seconds)) {
      return #err("Neuron needs to hit the minimum age threshold of 2 weeks");
    };

    let oldLevel = _neuronAchievementLevel.get(neuronId);
    let newLevel = verifyNeuronAchievementLevel(neuronInfo.stake_e8s);
    let rewardsDue = verifyIcpRewardsDue(oldLevel, newLevel);

    if (rewardsDue <= 0) {
      return #err("Neuron is not due any rewards");
    };

    // double spend prevention
    if (Option.isSome(_ongoingRewardTransfers.get(caller))) {
      return #err("Reward transfer already in progress");
    };
    _ongoingRewardTransfers.put(caller, neuronId);

    let transferResult = await canisterTransferIcp(getNeuronIcpAccount(neuronFullInfo.account), (rewardsDue + ICP_PROTOCOL_FEE));

    // initiate message 3
    switch (transferResult) {
      case (#Ok result) {
        ignore _ongoingRewardTransfers.remove(caller);

        _neuronAchievementLevel.put(neuronId, newLevel);
        _TotalIcpClaimed += (rewardsDue + ICP_PROTOCOL_FEE);
        return #ok("Reward successfully disbursed");
      };
      case (#Err result) {
        ignore _ongoingRewardTransfers.remove(caller);

        return #err("Failed to transfer rewards, please try again");
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
    if (neuronStake >= LEVEL_5.icp_amount_needed) {
      return LEVEL_5;
    } else if (neuronStake >= LEVEL_4.icp_amount_needed) {
      return LEVEL_4;
    } else if (neuronStake >= LEVEL_3.icp_amount_needed) {
      return LEVEL_3;
    } else if (neuronStake >= LEVEL_2.icp_amount_needed) {
      return LEVEL_2;
    } else {
      return LEVEL_1; // always at least level 1
    };
  };

  private func verifyIcpRewardsDue(oldLevel : ?AchievementLevel, newLevel : AchievementLevel) : Nat64 {
    switch (oldLevel) {
      case (?old) {
        switch ((old.level_id, newLevel.level_id)) {
          case (4, 5) { return LEVEL_5.icp_reward };
          case (3, 4) { return LEVEL_4.icp_reward };
          case (2, 3) { return LEVEL_3.icp_reward };
          case (1, 2) { return LEVEL_2.icp_reward };
          case (1, 3) { return LEVEL_2.icp_reward + LEVEL_3.icp_reward };
          case (1, 4) {
            return LEVEL_2.icp_reward + LEVEL_3.icp_reward + LEVEL_4.icp_reward;
          };
          case (1, 5) {
            return LEVEL_2.icp_reward + LEVEL_3.icp_reward + LEVEL_4.icp_reward + LEVEL_5.icp_reward;
          };
          case (2, 4) { return LEVEL_3.icp_reward + LEVEL_4.icp_reward };
          case (2, 5) {
            return LEVEL_3.icp_reward + LEVEL_4.icp_reward + LEVEL_5.icp_reward;
          };
          case (3, 5) { return LEVEL_4.icp_reward + LEVEL_5.icp_reward };
          case _ { return 0 }; // all transitions checked, reward is 0
        };
      };
      case (null) {
        // no previous level
        switch (newLevel.level_id) {
          case 5 {
            return LEVEL_1.icp_reward + LEVEL_2.icp_reward + LEVEL_3.icp_reward + LEVEL_4.icp_reward + LEVEL_5.icp_reward;
          };
          case 4 {
            return LEVEL_1.icp_reward + LEVEL_2.icp_reward + LEVEL_3.icp_reward + LEVEL_4.icp_reward;
          };
          case 3 {
            return LEVEL_1.icp_reward + LEVEL_2.icp_reward + LEVEL_3.icp_reward;
          };
          case 2 { return LEVEL_1.icp_reward + LEVEL_2.icp_reward };
          case _ { return LEVEL_1.icp_reward }; // minimum level 1 reward
        };
      };
    };
  };

  private func verifyNeuronIsStaking(neuronState : Int32, dissolveDelay : Nat64) : Bool {
    let minimumSecondsNeeded : Nat64 = 15_813_200; // minimum of 6 months

    if (neuronState == 1) {
      // locked
      return dissolveDelay >= minimumSecondsNeeded;
    } else {
      return false;
    };
  };

  private func verifyNeuronAge(age : Nat64) : Bool {
    let minimumSecondsNeeded : Nat64 = 1_209_600; // minimum of 2 weeks

    return age >= minimumSecondsNeeded; // age is 0 if dissolving
  };

  ///////////////////////////////////
  // Private ICP wallet Functions ///
  ///////////////////////////////////

  private func getCanisterAccount(caller : Principal) : async Result.Result<CanisterAccount, Text> {
    let canisterIcpBalance = await getCanisterIcpBalance();

    return #ok({
      icp_address = Hex.encode(getCanisterIcpAddress());
      icp_balance = canisterIcpBalance;
    });
  };

  private func getCanisterStats() : Result.Result<CanisterStats, Text> {
    return #ok({
      icp_claimed = _TotalIcpClaimed;
      ongoing_transfers = Iter.toArray<(Principal, Nat64)>(_ongoingRewardTransfers.entries());
      total_neurons_added = _neuronAchievementLevel.size();
    });
  };

  private func getCanisterIcpAddress() : [Nat8] {
    let ownerAccount = Principal.fromActor(thisCanister);
    let subAccount = IcpAccountTools.defaultSubaccount();

    return Blob.toArray(IcpAccountTools.accountIdentifier(ownerAccount, subAccount));
  };

  private func getNeuronIcpAccount(account : [Nat8]) : [Nat8] {
    let govPrincipal = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let icpAccount = IcpAccountTools.accountIdentifier(govPrincipal, Blob.fromArray(account));

    return Blob.toArray(icpAccount);
  };

  private func getCanisterIcpBalance() : async Nat64 {
    let balance = await IcpLedger.account_balance({
      account = getCanisterIcpAddress();
    });

    return balance.e8s;
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
