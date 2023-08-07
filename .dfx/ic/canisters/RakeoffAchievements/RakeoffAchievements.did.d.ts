import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';

export interface AchievementLevel {
  'level_id' : bigint,
  'icp_amount_needed' : bigint,
  'icp_reward' : bigint,
}
export interface CanisterAccount {
  'ongoing_transfers' : Array<[Principal, bigint]>,
  'icp_claimed' : bigint,
  'icp_address' : string,
  'icp_balance' : bigint,
}
export interface NeuronAchievementDetails {
  'neuron_passes_checks' : boolean,
  'current_level' : AchievementLevel,
  'cached_level' : [] | [AchievementLevel],
  'canister_rewards_available' : boolean,
  'reward_amount_due' : bigint,
  'neuron_id' : bigint,
}
export interface RakeoffAchievements {
  'check_achievement_level_reward' : ActorMethod<[bigint], Result_2>,
  'claim_achievement_level_reward' : ActorMethod<[bigint], Result_1>,
  'get_canister_account_and_stats' : ActorMethod<[], Result>,
  'show_available_levels' : ActorMethod<[], Array<AchievementLevel>>,
}
export type Result = { 'ok' : CanisterAccount } |
  { 'err' : string };
export type Result_1 = { 'ok' : string } |
  { 'err' : string };
export type Result_2 = { 'ok' : NeuronAchievementDetails } |
  { 'err' : string };
export interface _SERVICE extends RakeoffAchievements {}
