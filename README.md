# Repeat Last Dish

A Project Zomboid Build 42 mod. Cooking the same salad or stir fry ten times means ten trips through the same right-click menus. This mod remembers the ingredients you put into your last dish, in order, and makes it again.

## How it works

- Make a dish the usual way: right-click an empty bowl, pan or pot and add ingredients. The mod records the base item, the recipe and each ingredient in the order you added them.
- Next time, right-click an empty base of the same kind: **Repeat last dish: Salad**, at the top of the vanilla "Make Salad" submenu (at the end of the menu when nothing can go in right now). Select several bases to make several dishes in a row.
- The ingredients are taken from your inventory first, then from containers next to you (the fridge, counters, the floor): whatever the loot window shows. Fresh or stale doesn't matter (older ones go first); **rotten food is never used**. Frozen food is skipped unless the recipe allows it, as in vanilla.
- Each ingredient goes in with the normal "add ingredient" action and time; leftovers go back where they came from.
- The option is greyed out, with the missing ingredients in the tooltip, when something is not there. With several bases, it stops before a dish it can't finish. An ingredient that runs out halfway through a dish is skipped and reported.
- Cancel at any time like any other action.

## Cook what spoils first (0.1.3)

Right below the repeat option: **Cook what spoils first: Salad**. You choose the dish; the mod chooses the food that goes off soonest, and the tooltip lists it before you click.

- It follows the game's own rule (`EvolvedRecipe.addItem`): each ingredient sets the dish's unhappiness to `current - 5 + 5 * changer`, where `changer` is the number of the same ingredient already in it, plus `n - 2 - 3 * Cooking` once `n - 2 > Cooking` (`n` = ingredients already in). So a new ingredient gives -5, a 2nd of the same 0, a 3rd +5, and at Cooking 0 the 4th ingredient gives 0 and the 5th +5. Only adds of 0 or less go in, new ingredients first.
- Stale food has no penalty in a dish (its freshness comes from the bowl), so the food closest to rotting goes first.
- Then spices (they are not counted in that rule, and each lowers unhappiness and boredom): every spice that goes off, plus the 2 most plentiful that keep.
- Never used: rotten or burnt food, favourites, what you hold, food you know is poisoned, raw food that must be cooked for a dish that is never cooked, and wild mushrooms and berries (foraging poisons some at random and you can't tell which, so the whole kind is left out).
- With several bases, each dish is planned on what is left. The first dish becomes your last dish.

## Compatibility

- Client-side Lua; uses only vanilla actions, so the server needs nothing beyond having the mod in its list.
- Checked in single player and multiplayer (dedicated server, 0.1.2). "Cook what spoils first" is checked in single player only. Multiplayer: each step waits until the server's change shows in your inventory. 0.1.1 fixed dishes made on a server not being recorded (the state was read after the server's change had already arrived).
- Safe to add to or remove from an existing save. The last dish is kept in the player's mod data (single player) or in `Zomboid/Lua/RepeatLastDish_<server>_<name>.txt` on your PC (multiplayer).

## Install

[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3837665530), or copy `Contents/mods/RepeatLastDish` into `%USERPROFILE%\Zomboid\mods\`.

## Testing

`pzt live` in this folder (PZTestHarness). Scenarios: recording a hand-made salad, repeating two salads from a fridge with a rotten and a stale ingredient, missing ingredient, partial run, other base items, cancel, a spice (garlic) in the dish, the submenu position, the multiplayer order (server change before perform), and cook what spoils first (the rule's numbers, the plan at Cooking 0 and 3, two bowls, nothing to use).

## Support

If this mod helps you, you can support it via [Ko-fi](https://ko-fi.com/talkinghands2285) or [PayPal](https://www.paypal.com/paypalme/TalkingHands619/3). It's optional; every feature stays free.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/talkinghands2285)
