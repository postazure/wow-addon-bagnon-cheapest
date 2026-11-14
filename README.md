# Bagnon Cheapest

A [Bagnon](https://www.curseforge.com/wow/addons/bagnon) plugin for WoW Forever. It finds the lowest-value stack in your bags so you can free a slot in one click.

## Features

- Adds a button to Bagnon's bag window showing the item that would go next and its vendor price.
- Grey items come first. After that, items are ranked by vendor price × stack size.
- By default the button only offers grey items, so Shift-click is a quick way to clear junk. The list shows every quality.
- Hovering shows the next four candidates and darkens every other slot, so the target stands out.
- At a vendor it sells the stack instead of destroying it.
- A list panel shows every candidate. Exclude anything you want to keep; exclusions are saved for all your characters.

## Usage

| Where | Action | Result |
|---|---|---|
| Bag button | Click | Open or close the list |
| Bag button | Shift-click | Destroy (or sell) the cheapest stack |
| Bag button | Shift-right-click | Skip that item until you close your bags |
| List | Shift-click | Destroy (or sell) that stack |
| List | Right-click | Exclude that item |
| Excluded list | Right-click | Restore that item |

`/bcheap` toggles the list, and `/bcheap scan` prints the ranking to chat.

## Options

Under **Options → AddOns → Bagnon Cheapest**, or `/bcheap options`:

- **Button picks from:** which items the bag button (and its Shift-click) may pick. The default, *Poor (junk only)*, means grey items only. Pick *Common and below*, *Uncommon and below* and so on to let it pick better items too. The list always shows every quality.
- **Grey items first:** on by default, so grey junk always comes first and everything else follows by vendor value. Turn it off to rank everything by vendor value alone.

## Safety

- The slot is checked again before anything happens. If the item or stack size changed, nothing is done.
- Uncommon and better items always go through Blizzard's "type DELETE" confirmation.
- Works in combat (destroying only; selling waits until combat ends). Nothing happens while your cursor is holding an item.
- Quest items and items with no sell price are never listed.
- Selling skips items that can still be refunded. Anything sold can be bought back from the vendor.

## Requirements

- WoW Forever (interface 16001)
- Bagnon

## Development

The ranking logic and a stubbed-API smoke test run outside the game:

```bash
pip install lupa
python tests/run.py
```

## Releasing

Pushing an annotated `v<version>` tag on `main` runs the Release workflow. It checks the tag against the `.toc` version and `CHANGELOG.md`, then tests, zips, creates the GitHub release and uploads to CurseForge. The tag's message is the release notes. The release skill in `.claude/skills/release` walks through it.

The CurseForge upload is skipped until the repo has a `CURSEFORGE_TOKEN` secret and a `CURSEFORGE_PROJECT_ID` variable.

## License

MIT. See [LICENSE](LICENSE).
