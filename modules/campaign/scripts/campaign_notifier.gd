## The signal half of [Campaign], which is all statics and so cannot declare
## one itself. Screens connect to [code]Campaign.notifier.changed[/code].
class_name CampaignNotifier
extends RefCounted

## Coins, ships, pips, records or the route changed.
signal changed
