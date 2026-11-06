# Bagnon Cheapest

A [Bagnon](https://www.curseforge.com/wow/addons/bagnon) plugin for WoW Forever. It finds the lowest-value stack in your bags so you can free a slot in one click.

## Features

- Adds a button to Bagnon's bag window showing the item that would go next and its vendor price.
- Grey items come first. After that, items are ranked by vendor price × stack size.
- Hovering shows the next four candidates and darkens every other slot, so the target stands out.
- At a vendor it sells the stack instead of destroying it.
- A list panel shows every candidate. Exclude anything you want to keep; exclusions are saved for all your characters.

## Usage

| Where | Action | Result |
|---|---|---|
| Bag button | Click | Open or close the list |
| Bag button | Shift-click | Destroy (or sell) the cheapest stack |
| List | Left-click | Destroy (or sell) that stack |
| List | Right-click | Exclude that item |
| Excluded list | Right-click | Restore that item |

`/bcheap` toggles the list, and `/bcheap scan` prints the ranking to chat.

## Safety

- The slot is checked again before anything happens. If the item or stack size changed, nothing is done.
- Uncommon and better items always go through Blizzard's "type DELETE" confirmation.
- Nothing happens in combat or while your cursor is holding an item.
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

## License

MIT. See [LICENSE](LICENSE).
