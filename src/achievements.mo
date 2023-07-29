import IcpLedgerInterface "./ledger_interface/ledger";
import IcpAccountTools "./ledger_interface/account";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Hex "mo:encoding/Hex";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Time "mo:base/Time";

// Welcome to the Rakeoff Achievements smart contract
// This smart contract must be made HotKey of the neuron used.
// A hotkey has access to a neurons full data.
// A hotkey can only vote, make proposals and change the following of a neuron.

shared ({ caller = owner }) actor class RakeoffAchievements() = thisCanister {

  /////////////////
  // Constants ////
  /////////////////

  // ICP ledger canister
  let IcpLedger = actor "ryjl3-tyaaa-aaaaa-aaaba-cai" : IcpLedgerInterface.Self;

  // The standard ICP transaction fee
  let ICP_PROTOCOL_FEE : Nat64 = 10_000;

  /////////////
  // Types ////
  /////////////

  public type CanisterAccount = {
    icp_address : Text;
    icp_balance : Nat64;
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
