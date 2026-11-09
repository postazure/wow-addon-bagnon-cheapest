"""Fails if the addon calls a :Method( that Forever's widget API docs don't list,
unless it is a known non-widget method (Bagnon, Blizzard Lua mixins).
Catches things like SetObeyStepMinMax, which doesn't exist on Forever."""
import glob
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
documented = {
    line.strip() for line in open(os.path.join(root, 'tests', 'forever_widget_methods.txt'), encoding='utf-8')
    if line.strip() and not line.startswith('#')
}

# Verified another way: GameTooltip methods used by Bagnon/Disenchantry on Forever,
# Bagnon's own class methods, ItemLocationMixin (Lua), and our event handlers.
known = {
    'AddLine', 'AddDoubleLine', 'SetOwner', 'IsOwned', 'SetBagItem', 'SetHyperlink',
    'Get', 'IsCached', 'Layout', 'GetExtraButtons',
    'GetBagAndSlot',
    # Settings API objects (used the same way by NodeSight on Forever).
    'SetValueChangedCallback', 'Add', 'GetData', 'GetID',
}

bad = []
for path in sorted(glob.glob(os.path.join(root, 'Bagnon_Cheapest', '*.lua'))):
    for n, line in enumerate(open(path, encoding='utf-8'), 1):
        # Widget methods are PascalCase; lowercase ones are Lua string methods.
        for method in re.findall(r':([A-Z]\w*)\(', line):
            if method.isupper() or method.startswith(('PLAYER_', 'BAG_', 'GET_')):
                continue  # our event handlers
            if method not in documented and method not in known:
                bad.append('%s:%d  %s' % (os.path.relpath(path, root), n, method))

for b in bad:
    print('UNKNOWN METHOD ' + b)
print('method check: %d unknown' % len(bad))
sys.exit(1 if bad else 0)
