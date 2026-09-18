# Console Vehicle Spawner (FS22)

Enable the mod for a savegame and enable the FS22 developer console. Commands must be run by the local host.

## Commands

```text
listSpawnVehicles [filter]
spawnVehicle STORE_INDEX [distance] [free]
```

Examples:

```text
listSpawnVehicles fendt
listSpawnVehicles trailer
spawnVehicle 142
spawnVehicle 142 12
spawnVehicle 142 8 free
```

`listSpawnVehicles` writes matching item indices, names, default prices, and XML paths to the console and `log.txt`. The index is the current session's GIANTS store index, so look it up after changing the active mod set.

`spawnVehicle` places the item in front of the host (8 metres by default; allowed range 4–50 metres), assigns it to the host's farm, and uses its default shop configuration. The full default shop price is deducted only after FS22 confirms that the item loaded successfully. The command refuses the purchase if the farm lacks the money.

Add `free` as the third argument to skip the affordability check and money deduction:

```text
spawnVehicle 142 8 free
```

The spawned vehicle keeps its normal shop value even in free mode, so subsequent selling and value calculations remain correct.

If a broken vehicle mod never completes FS22's asynchronous loader, the pending request is released after 30 seconds and the farm is not charged. A stack overflow or XML/I3D failure inside another mod cannot be bypassed by the spawner because the shop and console command use the same GIANTS vehicle loader; repair or remove the offending vehicle mod.

## FS19 ExtendedAnimationSounds compatibility

Some converted vehicle mods bundle an old `ExtendedAnimationSounds.lua` that replaces FS22's global `AnimatedVehicle.updateAnimation` function when one of their vehicles loads. This can make unrelated base-game and mod vehicles hang in the shop. The spawner captures the original GIANTS function before savegame vehicles load and restores it if an incompatible mod replaces it. Each repair is recorded in `log.txt`.

Clear enough space in front of the player before spawning large equipment. A dedicated-server console has no player position, so spawning from a headless dedicated-server console is intentionally rejected.
