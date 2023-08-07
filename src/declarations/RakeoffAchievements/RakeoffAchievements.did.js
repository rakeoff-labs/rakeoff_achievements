export const idlFactory = ({ IDL }) => {
  const AchievementLevel = IDL.Record({
    'level_id' : IDL.Nat,
    'icp_amount_needed' : IDL.Nat64,
    'icp_reward' : IDL.Nat64,
  });
  const NeuronAchievementDetails = IDL.Record({
    'neuron_passes_checks' : IDL.Bool,
    'current_level' : AchievementLevel,
    'cached_level' : IDL.Opt(AchievementLevel),
    'canister_rewards_available' : IDL.Bool,
    'reward_amount_due' : IDL.Nat64,
    'neuron_id' : IDL.Nat64,
  });
  const Result_2 = IDL.Variant({
    'ok' : NeuronAchievementDetails,
    'err' : IDL.Text,
  });
  const Result_1 = IDL.Variant({ 'ok' : IDL.Text, 'err' : IDL.Text });
  const CanisterAccount = IDL.Record({
    'ongoing_transfers' : IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Nat64)),
    'icp_claimed' : IDL.Nat64,
    'icp_address' : IDL.Text,
    'icp_balance' : IDL.Nat64,
  });
  const Result = IDL.Variant({ 'ok' : CanisterAccount, 'err' : IDL.Text });
  const RakeoffAchievements = IDL.Service({
    'check_achievement_level_reward' : IDL.Func([IDL.Nat64], [Result_2], []),
    'claim_achievement_level_reward' : IDL.Func([IDL.Nat64], [Result_1], []),
    'get_canister_account_and_stats' : IDL.Func([], [Result], []),
    'show_available_levels' : IDL.Func(
        [],
        [IDL.Vec(AchievementLevel)],
        ['query'],
      ),
  });
  return RakeoffAchievements;
};
export const init = ({ IDL }) => { return []; };
