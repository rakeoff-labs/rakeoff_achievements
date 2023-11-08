import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';

export interface AchievementLevel {
  'level_id' : bigint,
  'icp_amount_needed' : bigint,
  'icp_reward' : bigint,
}
export interface CanisterAccount {
  'icp_address' : string,
  'icp_balance' : bigint,
}
export interface CanisterStats {
  'ongoing_transfers' : Array<[Principal, bigint]>,
  'icp_claimed' : bigint,
  'total_neurons_added' : bigint,
}
export interface NeuronAchievementDetails {
  'neuron_passes_checks' : boolean,
  'current_level' : AchievementLevel,
  'cached_level' : [] | [AchievementLevel],
  'neuron_checks' : NeuronCheckResults,
  'reward_amount_due' : bigint,
  'neuron_id' : bigint,
}
export interface NeuronCheckArgs {
  'dissolve_delay_seconds' : bigint,
  'state' : number,
  'stake_e8s' : bigint,
  'neuronId' : bigint,
  'age_seconds' : bigint,
}
export interface NeuronCheckResults {
  'is_staking' : boolean,
  'is_locked_for_6_months' : boolean,
  'two_weeks_old' : boolean,
  'new_achievement_reward_due' : boolean,
}
export interface RakeoffAchievements {
  'check_achievement_level_reward' : ActorMethod<[NeuronCheckArgs], Result_3>,
  'claim_achievement_level_reward' : ActorMethod<[bigint], Result_2>,
  'get_canister_account' : ActorMethod<[], Result_1>,
  'get_canister_stats' : ActorMethod<[], Result>,
  'show_available_levels' : ActorMethod<[], Array<AchievementLevel>>,
}
export type Result = { 'ok' : CanisterStats } |
  { 'err' : string };
export type Result_1 = { 'ok' : CanisterAccount } |
  { 'err' : string };
export type Result_2 = { 'ok' : string } |
  { 'err' : string };
export type Result_3 = { 'ok' : NeuronAchievementDetails } |
  { 'err' : string };
export interface _SERVICE extends RakeoffAchievements {}
