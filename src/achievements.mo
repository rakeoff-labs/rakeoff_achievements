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

  // Achievement levels (amount of ICP e8s needed in neuron)
  let ACHIEVEMENTS_LEVEL_1 : Nat64 = 100000000; // 1 ICP

  let ACHIEVEMENTS_LEVEL_2 : Nat64 = 1000000000; // 10 ICP

  let ACHIEVEMENTS_LEVEL_3 : Nat64 = 10000000000; // 100 ICP

  /////////////
  // Types ////
  /////////////

  public type AchievementLevel = Nat64;

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

  private var _neuronLevel = HashMap.HashMap<Nat64, AchievementLevel>(
    10,
    Nat64.equal,
    nat64Hash,
  );

  // Maintain hashmap state
  private stable var _neuronLevelStorage : [(Nat64, AchievementLevel)] = [];

  system func preupgrade() {
    _neuronLevelStorage := Iter.toArray(_neuronLevel.entries());
  };

  system func postupgrade() {
    _neuronLevel := HashMap.fromIter(
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

  ////////////////////////
  // Private Functions ///
  ////////////////////////

  private func claimAchievementLevelReward(caller : Principal, neuronId : Nat64) : async Result.Result<Text, Text> {
    // verify owner:
    let isOwner = await verifyCallerOwnsNeuron(caller, neuronId);

    switch(isOwner){
      case(#ok result){
        // check achievement level
      };
      case(#err result){
        return #err(result)
      }
    }
  };

  private func verifyCallerOwnsNeuron(caller : Principal, neuronId : Nat64) : async Result.Result<Bool, Text> {
    let dataResult = await Governance.get_full_neuron(neuronId);

    switch (dataResult) {
      case (#Ok result) {
        switch (result.controller) {
          case (?controller) {
            return #ok(Principal.equal(controller, caller));
          };
          case (null) {
            return #err("Failed to get neuron controller");
          };
        };
      };
      case (#Err result) {
        return #err("Failed to get neuron data");
      };
    };
  };

  private func verifyNeuronAchievementLevel(neuronId : Nat64) : async Result.Result<Nat64, Text> {
    let dataResult = await Governance.get_full_neuron(neuronId);

    switch (dataResult) {
      case (#Ok result) {
        if (result.cached_neuron_stake_e8s >= ACHIEVEMENTS_LEVEL_3) {
          return #ok(ACHIEVEMENTS_LEVEL_3);
        } else if (result.cached_neuron_stake_e8s >= ACHIEVEMENTS_LEVEL_2) {
          return #ok(ACHIEVEMENTS_LEVEL_2);
        } else if (result.cached_neuron_stake_e8s >= ACHIEVEMENTS_LEVEL_1) {
          return #ok(ACHIEVEMENTS_LEVEL_1);
        } else {
          return #err("Neuron failed to match an achievement level");
        };
      };
      case (#Err result) {
        return #err("Failed to get neuron data");
      };
    };
  };

  // ICP wallet functions:
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
