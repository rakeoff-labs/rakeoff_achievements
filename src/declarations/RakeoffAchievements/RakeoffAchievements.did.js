export const idlFactory = ({ IDL }) => {
  const NeuronCheckArgs = IDL.Record({
    'dissolve_delay_seconds' : IDL.Nat64,
    'state' : IDL.Int32,
    'stake_e8s' : IDL.Nat64,
    'neuronId' : IDL.Nat64,
    'age_seconds' : IDL.Nat64,
  });
  const AchievementLevel = IDL.Record({
    'level_id' : IDL.Nat,
    'icp_amount_needed' : IDL.Nat64,
    'icp_reward' : IDL.Nat64,
  });
  const NeuronCheckResults = IDL.Record({
    'is_staking' : IDL.Bool,
    'is_locked_for_6_months' : IDL.Bool,
    'two_weeks_old' : IDL.Bool,
    'new_achievement_reward_due' : IDL.Bool,
  });
  const NeuronAchievementDetails = IDL.Record({
    'neuron_passes_checks' : IDL.Bool,
    'current_level' : AchievementLevel,
    'cached_level' : IDL.Opt(AchievementLevel),
    'neuron_checks' : NeuronCheckResults,
    'reward_amount_due' : IDL.Nat64,
    'neuron_id' : IDL.Nat64,
  });
  const Result_3 = IDL.Variant({
    'ok' : NeuronAchievementDetails,
    'err' : IDL.Text,
  });
  const Result_2 = IDL.Variant({ 'ok' : IDL.Text, 'err' : IDL.Text });
  const CanisterAccount = IDL.Record({
    'icp_address' : IDL.Text,
    'icp_balance' : IDL.Nat64,
  });
  const Result_1 = IDL.Variant({ 'ok' : CanisterAccount, 'err' : IDL.Text });
  const CanisterStats = IDL.Record({
    'ongoing_transfers' : IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Nat64)),
    'icp_claimed' : IDL.Nat64,
    'total_neurons_added' : IDL.Nat,
  });
  const Result = IDL.Variant({ 'ok' : CanisterStats, 'err' : IDL.Text });
  const RakeoffAchievements = IDL.Service({
    'check_achievement_level_reward' : IDL.Func(
        [NeuronCheckArgs],
        [Result_3],
        ['query'],
      ),
    'claim_achievement_level_reward' : IDL.Func([IDL.Nat64], [Result_2], []),
    'get_canister_account' : IDL.Func([], [Result_1], []),
    'get_canister_stats' : IDL.Func([], [Result], ['query']),
    'show_available_levels' : IDL.Func(
        [],
        [IDL.Vec(AchievementLevel)],
        ['query'],
      ),
  });
  return RakeoffAchievements;
};
export const init = ({ IDL }) => { return []; };
