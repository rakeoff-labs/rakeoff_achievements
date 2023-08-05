# `RakeoffAchievements()`

This repo contains the smart contract code for the Rakeoff Achievements system that rewards users who stake on the Rakeoff dApp.

You can visit the Rakeoff dApp here [app.rakeoff.io](https://app.rakeoff.io/)

## Overview of the tech stack

- [Motoko](https://react.dev/](https://internetcomputer.org/docs/current/motoko/main/motoko?source=nav)) is used for the smart contract programming language.
- The IC SDK: [DFX](https://internetcomputer.org/docs/current/developer-docs/setup/install) is used to make this an ICP project.

### How does it work?
The smart contract has 5 achievement levels and rewards users a small amount of ICP based on their `stake_e8s` amount in their neurons, the ICP reward is then added to the neuron. The smart contract performs the following verifications to reward users:
- The caller owns the neuron they are submitting.
- The neuron is in a locked state and staked for at least 6 months.
- The neuron is at least 2 weeks old.
- The neuron has reached the minimum ICP required for a particular achievement level.

*In order to perform these verifications the smart contract must be made Hot Key of the neuron submitted.*

### Bug bounties
While the smart contract only holds a modest balance of ICP for rewards disbursement (typically below 30 ICP), and level 1 neuron rewards stand at under 0.05 ICP, we recognize the significance of ensuring its security. Should you identify a vulnerability or flaw that jeopardizes funds or reward allocations, we commit to offering a bounty that exceeds the potential gains from malicious exploitation. To report any findings, please reach out to the Rakeoff team at: crew@rakeoff.io.

### If you want to clone onto your local machine

Make sure you have `git` and `dfx` installed
```bash
# clone the repo
git clone #<get the repo ssh>

# change directory
cd rakeoff_achievements

# set up the dfx local server
dfx start --background --clean

# deploy the canisters locally
dfx deploy

# ....
# when you are done make sure to stop the local server:
dfx stop
```

## License

The `RakeoffAchievements()` smart contract code is distributed under the terms of the Apache 2.0 License.

See LICENSE for details.
