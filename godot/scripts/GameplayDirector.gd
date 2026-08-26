extends Node3D

signal vendor_requested(vendor_data: Dictionary)
signal crafting_requested(station_data:Dictionary)
signal notification_requested(message:String,color:Color)
signal lore_requested(title:String,body:String)
signal zone_travel_requested(zone_id:String,entry_edge:String)

const IMP_SCENE: PackedScene = preload("res://assets/enemies/imp_enemy.glb")
const DRAGON_SCENE: PackedScene = preload("res://assets/enemies/cave_dragon.glb")
const ASHFANG_SCENE: PackedScene = preload("res://assets/enemies/ashfang_hound.glb")
const GRAVEBOUND_SCENE:PackedScene=preload("res://assets/enemies/gravebound_zombie.glb")
const FROST_TROLL_SCENE:PackedScene=preload("res://assets/enemies/frost_troll_v1.glb")
const RIMECRAWLER_SCENE:PackedScene=preload("res://assets/enemies/rimecrawler_v1.glb")
const ASHSCALE_BASILISK_SCENE:PackedScene=preload("res://assets/enemies/ashscale_basilisk_v1.glb")
const RIME_CHITIN_DROP_SCENE:PackedScene=preload("res://assets/items/rime_chitin_pickup_v1.glb")
const DEER_SCENE:PackedScene=preload("res://assets/animals/highland_deer_v1.glb")
const HARE_SCENE:PackedScene=preload("res://assets/animals/highland_hare_v1.glb")
const GROUSE_SCENE:PackedScene=preload("res://assets/animals/highland_grouse_v1.glb")
const VENISON_SCENE:PackedScene=preload("res://assets/animals/venison_cut_v1.glb")
const GRAVEBOUND_CAMPAIGN_SCRIPT:=preload("res://scripts/gameplay/GraveboundCampaign.gd")
const OATHBOUND_CAMPAIGN_SCRIPT:=preload("res://scripts/gameplay/OathboundCampaign.gd")
const ZOMBIE_GROAN:AudioStream=preload("res://assets/audio/gravebound/groan.wav")
const ZOMBIE_ATTACK:AudioStream=preload("res://assets/audio/gravebound/attack.wav")
const ZOMBIE_HIT:AudioStream=preload("res://assets/audio/gravebound/hit.wav")
const ZOMBIE_DEATH:AudioStream=preload("res://assets/audio/gravebound/death.wav")
const AXE_SCENE:PackedScene=preload("res://assets/items/axe_v2.glb")
const FISHING_POLE_SCENE:PackedScene=preload("res://assets/items/fishing_pole.glb")
const FISH_SCENE:PackedScene=preload("res://assets/items/fish.glb")
const COOKED_FISH_SCENE:PackedScene=preload("res://assets/items/cooked_fish.glb")
const BERRIES_SCENE:PackedScene=preload("res://assets/items/berries.glb")
const LOG_SCENE:PackedScene=preload("res://assets/items/log.glb")
const COIN_POUCH_SCENE:PackedScene=preload("res://assets/items/coin_pouch.glb")
const ARMOR_DROP_SCENE:PackedScene=preload("res://assets/items/armor_bundle.glb")
const CRYSTAL_DROP_SCENE:PackedScene=preload("res://assets/items/crystal.glb")
const SWORD_DROP_SCENE:PackedScene=preload("res://assets/items/sword.glb")
const SHIELD_DROP_SCENE:PackedScene=preload("res://assets/items/shield.glb")
const ORE_DROP_SCENE:PackedScene=preload("res://assets/items/ore.glb")
const CHOPPABLE_TREE_SCENE:PackedScene=preload("res://assets/items/choppable_tree.glb")
const FELLED_TREE_LINGER_SECONDS:=4.0
const FISHING_MAX_CAST_DISTANCE:=8.5

var player: CharacterBody3D
var height_sampler: Callable
var walkable_sampler: Callable
var minions: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var cooldowns := [0.0, 0.0, 0.0, 0.0]
var rng := RandomNumberGenerator.new()
var loot: Array[Dictionary] = []
var _spawn_count := 0
var quest_title := "Riverbank Menace"
var quest_goal := 8
var quest_complete := false
var profile: Dictionary = {}
var skill_levels := [1,1,1,1]
var skill_xp := [0,0,0,0]
var nearby_vendor := ""
var nearby_vendor_data: Dictionary = {}
var safe_zone_center := Vector2.ZERO
var safe_zone_radius := 68.0
var _vendors: Array[Node3D] = []
var _vendor_scan_cooldown := 0.0
var _minion_tick_accumulator := 0.0
var _portals: Array[Dictionary] = []
var _nearby_portal: Dictionary = {}
var _portal_cooldown := 0.0
var _service_material_cache: Dictionary = {}
var _magic_requirement_time := 0.0
var _interactables:Array[Dictionary]=[]
var _nearby_interactable:Dictionary={}
var _nearby_loot:Dictionary={}
var _gathered_counts:Dictionary={"herbs":0,"logs":0,"ore":0,"crafted":0,"dungeons":0,"ashfangs":0,"ashscale_basilisks":0,"rimecrawlers":0,"rimecraft":0,"marcher_threats":0,"marcher_secrets":0,"rainward_threats":0,"rainward_secrets":0,"stormbreak_threats":0,"stormbreak_secrets":0,"skeld_threats":0,"skeld_secrets":0,"fish":0}
var _quest_claimed:Dictionary={}
var _quest_baselines:Dictionary={"road_imps":0}
var _stream_tick:=0.0
var _stream_transition_queue:Array[Dictionary]=[]
var _stream_transition_sequence:=0
var _stream_transition_frame:=0
var _last_stream_transition:Dictionary={}
var _stream_scene_branches:=false
var _collision_refresh_tick:=0.0
var _collision_refresh_sequence:=0
var _last_collision_refresh:Dictionary={}
var _admin_one_hit_kill:=false
var _admin_god_mode:=false
var _forest_trees:Array[Dictionary]=[]
var _tree_buckets:Dictionary={}
var _nearby_world_tree:Dictionary={}
var _fishing_active:=false
var _fishing_phase:=""
var _fishing_timer:=0.0
var _fishing_spot:Dictionary={}
var _fishing_elapsed:=0.0
var _fishing_visual:Node3D
var _fishing_bobber:Node3D
var _fishing_line:MeshInstance3D
var _fishing_ripple:MeshInstance3D
var _fishing_fish_shadow:MeshInstance3D
var _fishing_target:=Vector3.ZERO
var _local_prop_collision_body:StaticBody3D
var _local_prop_collision_shapes:Array[CollisionShape3D]=[]
var _active_prop_collision_slots:Dictionary={}
var _prop_collision_slot_keys:Array[String]=[]
var _rock_collision_registry:Array=[]
var _prop_collision_buckets:Dictionary={}
var _last_prop_collision_refresh_position:=Vector3(INF,INF,INF)
var _active_prop_collision_signature:=""
const LOCAL_PROP_COLLISION_REFRESH_DISTANCE:=3.0
var _mineable_rocks:Array[Dictionary]=[]
var _mineable_rock_buckets:Dictionary={}
var _nearby_world_rock:Dictionary={}
var _gravebound_campaign:Node3D
var _oathbound_campaign:Node3D
var _player_campfires:Array[Node3D]=[]
var _townfolk:Array[Dictionary]=[]
var _townfolk_tick_accumulator:=0.0

const QUESTS:=[
    {"id":"road_imps","chapter":"I","giver":"Captain Elowen, Riverwatch","title":"The Road to Crownspire","counter":"kills","goal":8,"requires":"","story":"The king's courier vanished on the capital road. Elowen needs the route cleared before she can recover the royal dispatch.","description":"Defeat hostile imps threatening the Crownspire road.","reward":"35 gold and a health potion"},
    {"id":"field_medicine","chapter":"II","giver":"Sister Mara, Riverwatch","title":"Mercy Before Rank","counter":"herbs","goal":8,"requires":"road_imps","story":"The recovered dispatch bears blood from an unknown attacker. Mara treats scouts, travelers, and suspected deserters before asking their allegiance.","description":"Gather medicinal herbs from the surrounding meadows.","reward":"30 gold and two health potions"},
    {"id":"river_provision","chapter":"III","giver":"Old Garran, West Ford","title":"A Patrol Must Eat","counter":"fish","goal":4,"requires":"field_medicine","story":"Garran saw forbidden torchlight under the old bridge. Feed his patrol and he will reveal the smugglers' trail toward Crownspire.","description":"Catch four fish. Equip the Fishing Pole, cast with E, then reel on the bite.","reward":"45 gold and a royal crystal"},
    {"id":"winter_wood","chapter":"IV","giver":"Warden Brann, Crownspire","title":"Timber for the Ramparts","counter":"logs","goal":10,"requires":"river_provision","story":"Someone has cut the northern watch platforms. Brann needs fresh timber before the saboteurs return.","description":"Chop trees and recover their fallen logs.","reward":"45 gold and a forester axe"},
    {"id":"first_forging","chapter":"V","giver":"Master Iven, Crownspire","title":"Reforge the Broken Seal","counter":"crafted","goal":4,"requires":"winter_wood","story":"Fragments from the watchtower carry the mark of the Broken Crown. Iven can restore the seal after testing your hand at the forge.","description":"Use town crafting stations to make four useful items.","reward":"55 gold and refined ore"},
    {"id":"deep_delver","chapter":"VI","giver":"Archivist Vale, Crownspire","title":"Keys Below","counter":"dungeons","goal":2,"requires":"first_forging","story":"The restored seal opens two forgotten vaults. Their final chests contain the proof Vale needs to name the traitor.","description":"Open the final reward chest in two dungeons.","reward":"90 gold and arcane essence"},
    {"id":"elite_hunt","chapter":"VII","giver":"Regent Aveline, Crownspire","title":"Champions of the Hollow King","counter":"elites","goal":5,"requires":"deep_delver","story":"The Hollow King's champions are gathering beyond the roads. Break their circle before they march on Crownspire.","description":"Defeat elite or boss monsters.","reward":"120 gold and a royal crystal"},
    {"id":"ashfang_packs","chapter":"Hunt","giver":"Warden Brann","title":"Ashfang Pack Hunt","counter":"ashfangs","goal":10,"requires":"road_imps","story":"Charred hounds have followed the Hollow King's spoor into the settled lands.","description":"Break the charred hound packs prowling beyond the settled roads.","reward":"80 gold and six pieces of leather"},
    {"id":"marcher_beacon","chapter":"East I","giver":"Marshal Teren, March Keep","title":"Ash Beneath the Beacon","counter":"marcher_threats","goal":10,"requires":"road_imps","story":"Cinderwatch has answered March Keep with the wrong flame: three short fires where one steady beacon should burn. Teren believes the new basilisk brood is being driven down Embercrag by someone searching the old signal vaults.","description":"Defeat ten hostiles in the Eastern Marches and clear the Dawnway approaches to Cinderwatch.","reward":"145 gold, basalt iron, and a Marchwarden lamellar"},
    {"id":"marcher_oath","chapter":"East II","giver":"Keeper Sava, Cinderwatch","title":"What Ember Span Swore","counter":"marcher_secrets","goal":2,"requires":"marcher_beacon","story":"The bridge oath names two witnesses: the tollmaster who watched the west road and the barrow keeper who watched the dead. Sava needs both surviving records before she relights Cinderwatch under the Broken Crown.","description":"Recover two concealed Eastern Marches caches tied to the old bridge oath.","reward":"190 gold and the Emberglass Oath Band"},
    {"id":"rainward_patrol","chapter":"West I","giver":"Warden Maelin, Oakrest","title":"Bells in the Rain","counter":"rainward_threats","goal":8,"requires":"road_imps","story":"The bell at Old Rainward Abbey has sounded three times without a hand on its rope. Maelin's patrols found claw marks leading from the ruined cloister toward the realmway.","description":"Defeat eight hostiles in the Western Reaches and make the road safe for Rainhaven's caravans.","reward":"105 gold, treated leather, and the Rainward patrol mark"},
    {"id":"rainward_reliquary","chapter":"West II","giver":"Brother Hale, Rainhaven","title":"The Abbot's Last Crossing","counter":"rainward_secrets","goal":1,"requires":"rainward_patrol","story":"The abbey ledger names a reliquary hidden above the flood line. Hale believes it contains the old wardens' proof that the Rainfall River once marked a royal boundary.","description":"Find one concealed cache in the Western Reaches.","reward":"135 gold and a Tideglass Signet"},
    {"id":"stormbreak_beacon","chapter":"Highlands I","giver":"Warden Cael, Stormbreak Hold","title":"Fire on Stormscar","counter":"stormbreak_threats","goal":10,"requires":"rainward_patrol","story":"Stormscar Beacon has gone dark while ashfangs and old dead gather around its road. Cael cannot signal Greyfen or Galehorn until the ridge is cleared.","description":"Defeat ten hostiles in the Stormbreak Highlands and reopen the beacon roads.","reward":"150 gold, highland iron, and a Stormward mantle"},
    {"id":"stormbreak_choir","chapter":"Highlands II","giver":"Keeper Eira, Moorwatch","title":"The Hymn Beneath Thunder","counter":"stormbreak_secrets","goal":2,"requires":"stormbreak_beacon","story":"The Shattered Choir sang once before every crown war. Eira believes its lost undercrypt and the beacon keeper's strongbox contain the two halves of a warning meant for Crownspire.","description":"Find two concealed caches in the Stormbreak Highlands.","reward":"185 gold and the Tempest Choir Band"},
    {"id":"skeld_lantern","chapter":"Coast I","giver":"Harbormaster Sigrun, Frostharbor","title":"Light Against the Grey","counter":"skeld_threats","goal":12,"requires":"stormbreak_choir","story":"Cape Keld's lantern still burns, but no keeper has reached Frostharbor in nine nights. Trolls, crawlers, and the chapel dead have cut every road between the harbor and the headland.","description":"Defeat twelve hostiles on the Skeld Coast and reopen the lightkeeper roads.","reward":"210 gold, saltsteel, and a Cape Keld watchcoat"},
    {"id":"skeld_bones","chapter":"Coast II","giver":"Cantor Yrsa, Whalebone Chapel","title":"The Bones Remember","counter":"skeld_secrets","goal":2,"requires":"skeld_lantern","story":"The old canticle says Cape Keld's light was built to watch something beneath the Grey Sea, not ships upon it. Yrsa needs the lightkeeper's storm record and the chapel reliquary before she can translate the final verse.","description":"Recover two concealed records from Cape Keld and Whalebone Chapel.","reward":"260 gold and the Greywake Lantern Band"},
    {"id":"rimecrawler_hunt","chapter":"VIII","giver":"Warden Ysra, Icewatch Hold","title":"Chitin Under Rime","counter":"rimecrawlers","goal":5,"requires":"elite_hunt","story":"The retreating ice has opened old brood tunnels beneath the Rimewater moraine. Ysra needs proof that the crawlers have not reached the road shelters.","description":"Investigate the marked nesting grounds and defeat five Rimecrawlers.","reward":"140 gold, two royal crystals, and the Icewatch Signet"},
    {"id":"last_light_armor","chapter":"IX","giver":"Armorer Kael, Icewatch Hold","title":"Armor for Last Light","counter":"rimecraft","goal":1,"requires":"rimecrawler_hunt","story":"Kael recognizes the shell as natural frostward. Bind it into field armor before the Last Light expedition climbs beyond Rimefall.","description":"Craft Rimecrawler Bracers at a town crafting yard.","reward":"160 gold and two arcane essence"},
]

const RECIPES:=[
    {"id":"health_tonic","category":"Alchemy","name":"Crimson Health Tonic","cost":{"herbs":3,"mushrooms":1},"kind":"health_potion","amount":1,"description":"Restores one health potion."},
    {"id":"mana_tonic","category":"Alchemy","name":"Azure Mana Draught","cost":{"herbs":3,"essence":1},"kind":"mana_potion","amount":1,"description":"Restores one mana potion."},
    {"id":"antidote","category":"Alchemy","name":"River Antidote","cost":{"herbs":2,"resin":1},"kind":"item","slot":"consumable","icon":10,"description":"A prepared antidote for later poison systems."},
    {"id":"focus_elixir","category":"Alchemy","name":"Focus Elixir","cost":{"mushrooms":2,"crystal":1},"kind":"item","slot":"consumable","icon":10,"mana":8,"description":"A concentrated magical reagent."},
    {"id":"oak_shield","category":"Weapons","name":"Oak Round Shield","cost":{"logs":5,"resin":2,"scrap":2},"kind":"gear","slot":"offhand","icon":9,"armor":9,"hp":14,"power":2,"description":"A resin-sealed shield faced with scavenged iron."},
    {"id":"iron_sword","category":"Weapons","name":"Riverguard Sword","cost":{"ore":6,"logs":2,"leather":2},"kind":"gear","slot":"mainhand","icon":8,"power":17,"hp":4,"description":"A dependable forged sword balanced for road fighting."},
    {"id":"forester_axe","category":"Weapons","name":"Forester Axe","cost":{"ore":4,"logs":3,"leather":1},"kind":"gear","slot":"mainhand","icon":8,"power":14,"description":"A broad axe suited to timber and battle."},
    {"id":"ash_staff","category":"Weapons","name":"Ashwood Channeling Staff","cost":{"logs":5,"crystal":2,"resin":2},"kind":"gear","slot":"mainhand","icon":6,"power":11,"mana":16,"description":"Ashwood wrapped around a stable arcane crystal."},
    {"id":"hunting_bow","category":"Weapons","name":"Yew Hunting Bow","cost":{"logs":4,"leather":2,"resin":1},"kind":"gear","slot":"mainhand","icon":8,"power":13,"description":"A future-ready ranged weapon with a strong yew stave."},
    {"id":"leather_cap","category":"Armor","name":"Boiled Leather Cap","cost":{"leather":4,"resin":1},"kind":"gear","slot":"head","icon":0,"armor":5,"hp":7,"description":"Hardened leather protection for travelers."},
    {"id":"hide_vest","category":"Armor","name":"Ranger Hide Vest","cost":{"leather":8,"cloth":3},"kind":"gear","slot":"chest","icon":1,"armor":9,"hp":18,"power":2,"description":"Layered hide that stays flexible on steep trails."},
    {"id":"iron_helm","category":"Armor","name":"Forged Iron Helm","cost":{"ore":7,"leather":2},"kind":"gear","slot":"head","icon":0,"armor":10,"hp":9,"description":"A practical closed helm."},
    {"id":"iron_cuirass","category":"Armor","name":"Forged Iron Cuirass","cost":{"ore":13,"leather":4,"cloth":2},"kind":"gear","slot":"chest","icon":1,"armor":18,"hp":26,"power":3,"description":"Heavy town-forged plate."},
    {"id":"trail_boots","category":"Armor","name":"Trailwarden Boots","cost":{"leather":5,"cloth":2,"resin":1},"kind":"gear","slot":"feet","icon":4,"armor":5,"hp":8,"description":"Gripped boots made for mountain paths."},
    {"id":"iron_gauntlets","category":"Armor","name":"Iron Gauntlets","cost":{"ore":5,"leather":2},"kind":"gear","slot":"hands","icon":3,"armor":6,"power":3,"description":"Articulated iron hand protection."},
    {"id":"warm_trousers","category":"Armor","name":"Highland Trousers","cost":{"cloth":5,"leather":2},"kind":"gear","slot":"pants","icon":7,"armor":4,"hp":10,"description":"Warm reinforced traveling trousers."},
    {"id":"rimecrawler_bracers","category":"Glacial Craft","name":"Rimecrawler Bracers","cost":{"chitin":4,"crystal":2,"leather":2},"kind":"gear","slot":"hands","visual":"hands","effect":"frostward","icon":3,"armor":11,"hp":14,"power":5,"description":"Layered crawler plates bound over warm leather. The blue carapace carries a visible frostward."},
    {"id":"marchwarden_lamellar","category":"Marcher Craft","name":"Marchwarden Lamellar","cost":{"ore":11,"leather":6,"cloth":3},"kind":"gear","slot":"chest","visual":"chest","icon":1,"armor":21,"hp":31,"mana":0,"power":5,"description":"Overlapping basalt-iron scales laced over ochre leather for long patrols between Ember Span and Cinderwatch."},
    {"id":"emberglass_oath_band","category":"Marcher Craft","name":"Emberglass Oath Band","cost":{"crystal":3,"ore":4,"essence":2},"kind":"gear","slot":"ring_right","visual":"magic ring","ring_design":"split_band","effect":"emberpulse","icon":10,"armor":3,"hp":14,"mana":8,"power":10,"description":"Two dark iron arcs hold a living bead of Embercrag glass. Its orange ward pulses when danger draws close."},
    {"id":"saltmeadow_roundshield","category":"Marcher Craft","name":"Saltmeadow Roundshield","cost":{"logs":5,"leather":4,"ore":5,"resin":2},"kind":"gear","slot":"offhand","visual":"shield","icon":9,"armor":15,"hp":24,"mana":0,"power":4,"description":"Poplar boards, rawhide, and a basalt-iron rim built for the exposed northern meadow road."},
    {"id":"rainward_cloak","category":"Rainward Craft","name":"Rainward Waxed Cloak","cost":{"cloth":5,"resin":3,"leather":2},"kind":"gear","slot":"shoulders","visual":"shoulders","icon":2,"armor":7,"hp":16,"power":3,"description":"A waxed wool road-cloak cut by Oakrest's woodwardens for weeks of western rain."},
    {"id":"mossglass_band","category":"Rainward Craft","name":"Mossglass Wayfinder Band","cost":{"crystal":2,"resin":2,"ore":3},"kind":"gear","slot":"ring_right","visual":"magic ring","ring_design":"spiral","effect":"windstep","icon":10,"armor":2,"hp":10,"mana":8,"power":6,"description":"Green river-glass turns within its silver setting and casts a visible wayfinding ward."},
    {"id":"stonecross_jack","category":"Rainward Craft","name":"Stonecross Mason's Jack","cost":{"ore":10,"stone":8,"leather":4},"kind":"gear","slot":"chest","icon":1,"armor":19,"hp":30,"power":4,"description":"Overlapping iron and quarry-leather plates built to turn falling stone."},
    {"id":"stormward_mantle","category":"Highland Craft","name":"Stormward Mantle","cost":{"cloth":6,"leather":4,"resin":3,"ore":2},"kind":"gear","slot":"shoulders","visual":"shoulders","effect":"windstep","icon":2,"armor":9,"hp":20,"power":5,"description":"Layered storm wool fastened with highland iron. Its split hem stays clear on steep roads."},
    {"id":"blacktarn_band","category":"Highland Craft","name":"Blacktarn Compass Band","cost":{"crystal":3,"ore":4,"essence":1},"kind":"gear","slot":"ring_left","visual":"magic ring","ring_design":"crown","effect":"frostward","icon":10,"armor":4,"hp":14,"mana":10,"power":7,"description":"Dark tarn glass set beneath a broken compass needle. A pale ward points toward safe ground."},
    {"id":"galehorn_spear","category":"Highland Craft","name":"Galehorn Road Spear","cost":{"ore":8,"logs":4,"leather":2},"kind":"gear","slot":"mainhand","visual":"sword","icon":7,"armor":2,"hp":8,"power":20,"description":"A long highland road blade balanced to keep ashfangs beyond shield reach."},
    {"id":"skeld_harpoon","category":"Skeld Craft","name":"Frostharbor Saltsteel Harpoon","cost":{"ore":9,"logs":4,"leather":3},"kind":"gear","slot":"mainhand","visual":"sword","icon":7,"armor":2,"hp":10,"power":23,"description":"A long, narrow saltsteel point fitted to a tarred ash shaft for sea beasts and road fighting."},
    {"id":"vardholm_watchcoat","category":"Skeld Craft","name":"Vardholm Sealhide Watchcoat","cost":{"leather":9,"cloth":6,"resin":4},"kind":"gear","slot":"chest","visual":"chest","effect":"frostward","icon":1,"armor":16,"hp":34,"mana":4,"power":4,"description":"Layered hide, dense wool, and waxed seams keep the Rimepass watch alive through freezing spray."},
    {"id":"greywake_band","category":"Skeld Craft","name":"Greywake Lantern Band","cost":{"crystal":3,"ore":4,"essence":2},"kind":"gear","slot":"ring_left","visual":"magic ring","ring_design":"split_band","effect":"frostward","icon":10,"armor":5,"hp":18,"mana":14,"power":9,"description":"A pale sea-glass lantern turns inside a salt-dark silver band, shedding a visible ward in cold mist."},
    {"id":"torch_bundle","category":"Supplies","name":"Pitch Torch Bundle","cost":{"logs":2,"resin":2,"cloth":1},"kind":"item","slot":"offhand","icon":5,"description":"Three long-burning dungeon torches."},
    {"id":"lockpick_set","category":"Supplies","name":"Lockpick Set","cost":{"scrap":4,"cloth":1},"kind":"item","slot":"tool","icon":9,"description":"Fine picks for future locked caches."},
    {"id":"rope","category":"Supplies","name":"Climbing Rope","cost":{"cloth":4,"resin":1},"kind":"item","slot":"tool","icon":10,"description":"A sturdy coil for expeditions."},
    {"id":"camp_kit","category":"Supplies","name":"Traveler Camp Kit","cost":{"logs":3,"cloth":4,"leather":2},"kind":"item","slot":"tool","icon":10,"use":"world_place_campfire","visual":"campfire","description":"Double-click from the bag on safe outdoor ground to build a cooking campfire."},
    {"id":"stone_block","category":"Materials","name":"Cut Stone Block","cost":{"stone":4},"kind":"material","material":"stone","amount":2,"description":"Two refined masonry blocks."},
    {"id":"steel_ingot","category":"Materials","name":"Steel Ingot","cost":{"ore":3,"scrap":2},"kind":"material","material":"ore","amount":2,"description":"Two purified metal ingots."},
    {"id":"treated_leather","category":"Materials","name":"Treated Leather","cost":{"leather":3,"resin":1},"kind":"material","material":"leather","amount":2,"description":"Two pieces of durable treated leather."},
    {"id":"royal_alloy","category":"Masterwork","name":"Royal Alloy Breastplate","cost":{"ore":18,"crystal":3,"essence":2,"leather":4},"kind":"gear","slot":"chest","icon":1,"armor":25,"hp":38,"mana":8,"power":7,"description":"Masterwork blue-steel plate bearing the Broken Crown crest."},
    {"id":"crest_shield","category":"Masterwork","name":"Broken Crown Crest Shield","cost":{"ore":10,"logs":5,"crystal":2,"resin":2},"kind":"gear","slot":"offhand","icon":9,"armor":19,"hp":27,"power":5,"description":"A royal shield carrying the realm's broken-crown-and-river crest."},
    {"id":"cooked_fish","category":"Cooking","name":"Cooked Fish","cost":{},"kind":"cook_food","ingredient_id":"raw_fish","description":"Cook one raw fish. Restores health and grants the strongest food buff."},
    {"id":"herb_mushroom_stew","category":"Cooking","name":"Herb & Mushroom Stew","cost":{"herbs":2,"mushrooms":3},"kind":"cook_food","food_name":"Herb & Mushroom Stew","buff_name":"Trailwise","duration":300.0,"buff_power":5,"health_regen":.32,"stamina_regen":5.0,"heal":18.0,"description":"A long-lasting trail meal that improves stamina recovery for five minutes."},
    {"id":"ember_roasted_mushrooms","category":"Cooking","name":"Ember-Roasted Mushrooms","cost":{"mushrooms":4,"resin":1},"kind":"cook_food","food_name":"Ember-Roasted Mushrooms","buff_name":"Emberwarm","duration":210.0,"buff_power":7,"health_regen":.20,"stamina_regen":3.0,"heal":12.0,"description":"A hot highland snack granting power and steady recovery."},
    {"id":"hunter_venison","category":"Cooking","name":"Hunter's Roast Venison","cost":{"raw_meat":2,"resin":1,"herbs":1},"kind":"cook_food","food_name":"Hunter's Roast Venison","buff_name":"Well Fed","duration":420.0,"buff_power":8,"health_regen":.48,"stamina_regen":4.5,"heal":28.0,"description":"Game meat roasted over a campfire. Grants strong recovery and power for seven minutes."},
    {"id":"graveward_tonic","category":"Gravecraft","name":"Graveward Tonic","cost":{"herbs":2,"grave_tokens":2,"plague_samples":1},"kind":"health_potion","amount":2,"unlock":"gravebound","description":"Two strong healing draughts brewed from purified Gravebound residue."},
    {"id":"ossuary_buckler","category":"Gravecraft","name":"Ossuary Buckler","cost":{"ore":5,"grave_tokens":6},"kind":"gear","slot":"offhand","visual":"shield","icon":9,"armor":14,"hp":18,"power":4,"unlock":"gravebound","description":"A compact warded shield forged from recovered burial iron."},
    {"id":"graveglass_sword","category":"Gravecraft","name":"Graveglass Sword","cost":{"ore":7,"crystal":1,"grave_tokens":7},"kind":"gear","slot":"mainhand","visual":"sword","icon":8,"power":21,"hp":5,"unlock":"gravebound","description":"A keen road blade edged with blue graveglass."},
    {"id":"plagueward_cap","category":"Gravecraft","name":"Plagueward Coif","cost":{"cloth":4,"leather":3,"plague_samples":3},"kind":"gear","slot":"head","icon":0,"armor":9,"hp":12,"power":2,"unlock":"gravebound","description":"A sealed coif treated against the Gravebound plague."},
]

func configure(hero: CharacterBody3D, height_call: Callable, walkable_call: Callable, world_profile: Dictionary = {}) -> void:
    _begin_configuration(hero,height_call,walkable_call,world_profile)
    var configure_started_usec:int=Time.get_ticks_usec()
    for stage_index in range(get_configuration_stage_count()):
        var step_started_usec:int=Time.get_ticks_usec()
        run_configuration_stage(stage_index)
        _profile_configure_step(get_configuration_stage_label(stage_index),configure_started_usec,step_started_usec)


func configure_streamed(hero:CharacterBody3D,height_call:Callable,walkable_call:Callable,world_profile:Dictionary={})->void:
    _begin_configuration(hero,height_call,walkable_call,world_profile)
    var configure_started_usec:int=Time.get_ticks_usec()
    for stage_index in range(get_configuration_stage_count()):
        await get_tree().process_frame
        var step_started_usec:int=Time.get_ticks_usec()
        run_configuration_stage(stage_index)
        _profile_configure_step(get_configuration_stage_label(stage_index),configure_started_usec,step_started_usec)


func get_configuration_stage_count()->int:return 9


func get_configuration_stage_label(stage_index:int)->String:
    var labels:Array[String]=[
        "enemies","town_services","dungeons","campaigns",
        "gathering_services","tree_registry","prop_collisions",
        "service_batching","initial_stream",
    ]
    return labels[stage_index] if stage_index>=0 and stage_index<labels.size() else "gameplay"


func _begin_configuration(hero:CharacterBody3D,height_call:Callable,walkable_call:Callable,world_profile:Dictionary)->void:
    player = hero; height_sampler = height_call; walkable_sampler = walkable_call
    profile = world_profile
    _stream_scene_branches=OS.get_environment("BROKEN_KNIGHT_STREAM_SCENE_BRANCHES")=="1"
    _stream_transition_queue.clear()
    _stream_transition_sequence=0
    _stream_transition_frame=0
    _last_stream_transition={}
    _collision_refresh_sequence=0
    _last_collision_refresh={}
    _last_prop_collision_refresh_position=Vector3(INF,INF,INF)
    _active_prop_collision_signature=""
    _vendors.clear()
    safe_zone_center = profile.get("spawn_site", {}).get("position", Vector2(player.global_position.x, player.global_position.z))
    rng.seed = 71291
    if player.has_signal("world_item_requested") and not player.world_item_requested.is_connected(_on_world_item_requested):
        player.world_item_requested.connect(_on_world_item_requested)


func run_configuration_stage(stage_index:int)->void:
    match stage_index:
        0:
            _build_region_encounters()
            _build_region_wildlife()
        1:_build_town_services()
        2:_build_dungeon_network()
        3:
            _gravebound_campaign=GRAVEBOUND_CAMPAIGN_SCRIPT.new()
            add_child(_gravebound_campaign)
            _gravebound_campaign.configure(self,player,profile)
            _oathbound_campaign=OATHBOUND_CAMPAIGN_SCRIPT.new()
            add_child(_oathbound_campaign)
            _oathbound_campaign.configure(self,player,profile)
        4:
            _build_crafting_stations()
            _scatter_gathering_nodes()
            _build_fishing_spots()
            _register_house_doors()
            _build_zone_exits()
            _build_region_discovery_sites()
        5:
            _configure_harvestable_world_trees()
        6:_configure_local_prop_collisions()
        7:_batch_static_service_geometry()
        8:
            # Hide distant dungeons and service clusters before play resumes.
            _stream_local_gameplay(true)


func _build_region_encounters()->void:
    var authored:Array=profile.get("encounter_sites",[])
    if authored.is_empty():
        # Legacy starting-region fallback. It remains deliberately well beyond
        # the safe spawn and is replaced automatically as that profile gains
        # authored encounter sites.
        for i in range(3):_spawn_minion(920.0+i*46.0,float(i)*2.399)
        for i in range(4):_spawn_bramble_wraith(1120.0+float(i)*70.0,float(i)*2.217+.42)
        for pack in range(3):
            var pack_distance:=1370.0+float(pack)*125.0
            var pack_angle:=.68+float(pack)*1.47
            _spawn_ashfang(pack_distance,pack_angle,false)
            _spawn_ashfang(pack_distance+5.0,pack_angle-.075,true)
            _spawn_ashfang(pack_distance+8.0,pack_angle+.090,true)
        return
    for site_index in range(authored.size()):
        var site:Dictionary=authored[site_index]
        var center:Vector2=site.get("position",Vector2.ZERO)
        var count:=clampi(int(site.get("count",3)),1,8)
        var radius:=maxf(8.0,float(site.get("radius",36.0)))
        var rank:=maxi(1,int(site.get("rank",int(profile.get("danger_tier",1)))))
        var enemy_kind:=str(site.get("enemy","imp"))
        for member in range(count):
            var angle:=float(member)*TAU/float(count)+float(site_index)*1.117
            var distance:=radius*(.34+.45*float((member*5+site_index)%7)/6.0)
            var point:=center+Vector2(cos(angle),sin(angle))*distance
            var position:=Vector3(point.x,0.0,point.y)
            if _inside_safe_zone(position):continue
            match enemy_kind:
                "ashfang":_spawn_ashfang(0.0,angle,member>0,position,rank)
                "bramble_wraith":_spawn_bramble_wraith(0.0,angle,position,rank)
                "frost_troll":_spawn_frost_troll(position,rank,member)
                "rimecrawler":_spawn_rimecrawler(position,rank,member)
                "ashscale_basilisk":_spawn_ashscale_basilisk(position,rank,member)
                "gravebound":
                    var variants:Array[String]=["runner","common","graveguard","carrier"]
                    _spawn_zombie(point,variants[member%variants.size()],str(site.get("name","regional_patrol")))
                    _scale_latest_region_enemy(rank)
                _:_spawn_minion(0.0,angle,position,rank)


func _build_region_wildlife()->void:
    # Wildlife is profile-authored so future biomes can declare their own
    # species and density without another hard-coded world-building branch.
    var sites:Array=profile.get("wildlife_sites",[])
    for site_index in range(sites.size()):
        var site:Dictionary=sites[site_index]
        var species:=str(site.get("species","deer"))
        var center:Vector2=site.get("position",Vector2.ZERO)
        var population:=clampi(int(site.get("count",4)),1,12)
        var range_radius:=maxf(35.0,float(site.get("radius",240.0)))
        for member in range(population):
            var angle:=fmod(float(member)*2.39996323+float(site_index)*.817,TAU)
            var distance:=range_radius*(.18+.66*float((member*7+site_index*3)%11)/10.0)
            var point:=center+Vector2(cos(angle),sin(angle))*distance
            var spawn:=Vector3(point.x,0.0,point.y)
            for attempt in range(7):
                if (not walkable_sampler.is_valid() or walkable_sampler.call(spawn.x,spawn.z)) and not _inside_safe_zone(spawn):break
                angle+=.61
                distance=minf(range_radius*.92,distance+13.0)
                spawn=Vector3(center.x+cos(angle)*distance,0.0,center.y+sin(angle)*distance)
            if walkable_sampler.is_valid() and not walkable_sampler.call(spawn.x,spawn.z):continue
            _spawn_wildlife(species,spawn,center,range_radius,member)


func _spawn_wildlife(species:String,position:Vector3,home_center:Vector2,home_radius:float,member:int)->void:
    var scene:PackedScene=DEER_SCENE
    var scale_value:=.82
    var health:=48.0
    var flee_speed:=7.4
    match species:
        "hare":scene=HARE_SCENE;scale_value=.70;health=12.0;flee_speed=6.8
        "grouse":scene=GROUSE_SCENE;scale_value=.76;health=9.0;flee_speed=5.4
    var root:=Node3D.new()
    root.name="Wildlife_%s_%02d"%[species.capitalize(),member]
    root.set_meta("always_streamed",true)
    add_child(root)
    root.global_position=_ground(position)
    root.scale=Vector3.ONE*scale_value
    var visual:=scene.instantiate() as Node3D
    if visual==null:
        root.queue_free()
        return
    visual.name="WildlifeVisual"
    root.add_child(visual)
    var body:=AnimatableBody3D.new()
    body.name="WildlifeCollision"
    body.collision_layer=1
    body.collision_mask=0
    body.sync_to_physics=true
    root.add_child(body)
    var shape_node:=CollisionShape3D.new()
    var capsule:=CapsuleShape3D.new()
    capsule.radius=.36 if species=="deer" else .24
    capsule.height=1.72 if species=="deer" else .72
    shape_node.shape=capsule
    shape_node.position=Vector3(0,.86 if species=="deer" else .35,0)
    body.add_child(shape_node)
    minions.append({
        "node":root,"hp":health,"max_hp":health,"phase":rng.randf_range(0,TAU),"attack":0.0,"windup":0.0,"knockback":Vector3.ZERO,
        "elite":false,"base_scale":scale_value,"animation":null,"anim_lock":0.0,"flash_time":0.0,"flash_material":null,"dead":false,"death_time":0.0,
        "dungeon":false,"floor_y":root.global_position.y,"bounds":Rect2(),"rank":1,"kind":"wildlife_%s"%species,"species":species,"collision":body,
        "home":home_center,"home_radius":home_radius,"wander_direction":Vector2(cos(float(member)*1.71),sin(float(member)*1.71)),
        "wander_time":rng.randf_range(1.5,5.5),"flee_speed":flee_speed,"moving":false,
    })


func _build_region_discovery_sites()->void:
    # Authored expedition camps are functional anchors, not decoration. Their
    # visible fire is built by WorldPreviewBuilder; this companion interaction
    # opens the existing cooking/rest system when the player reaches it.
    for camp_value in profile.get("camp_sites",[]):
        var camp:Dictionary=camp_value
        var camp_point:Vector2=camp.get("position",Vector2.ZERO)
        var camp_position:=_ground(Vector3(camp_point.x,0.0,camp_point.y))
        _interactables.append({
            "action":"campfire","position":camp_position,"radius":4.2,
            "label":"Cook and rest at %s"%camp.get("name","expedition camp"),
            "active":true,
            "station":{"name":camp.get("name","Expedition Campfire"),"kind":"cooking"},
        })
    for site_value in profile.get("lore_sites",[]):
        var site:Dictionary=site_value
        var point:Vector2=site.get("position",Vector2.ZERO)
        var root:=Node3D.new();root.name="Lore_%s"%str(site.get("name","Record")).validate_node_name();add_child(root)
        root.global_position=_ground(Vector3(point.x,0.0,point.y))
        var kind:=str(site.get("kind","book"))
        if kind=="book":
            _service_solid_box(root,Vector3(0,.52,0),Vector3(1.10,1.04,.70),Color(.20,.18,.15))
            _service_box(root,Vector3(0,1.12,0),Vector3(.74,.09,.54),Color(.28,.055,.035))
            _service_box(root,Vector3(0,1.18,-.01),Vector3(.64,.025,.46),Color(.75,.65,.45))
        else:
            _service_solid_box(root,Vector3(0,.80,0),Vector3(.92,1.60,.34),Color(.40,.42,.40))
            var writing:=Label3D.new();writing.text="FIRST THAW\nCROWN  •  RIVER  •  ROAD";writing.position=Vector3(0,1.00,-.19);writing.font_size=22;writing.pixel_size=.006;writing.modulate=Color(.11,.09,.06);root.add_child(writing)
        _set_geometry_range(root,120.0)
        _interactables.append({
            "action":"read_lore","position":root.global_position,"radius":3.2,
            "label":"Read %s"%site.get("name","record"),"node":root,"active":true,
            "title":site.get("name","Recovered Record"),"entry":site.get("entry",""),
        })
    for site_value in profile.get("secret_sites",[]):
        var site:Dictionary=site_value
        var secret_key:="secret_cache:%s"%str(site.get("name","cache"))
        if bool(_quest_claimed.get(secret_key,false)):continue
        var point:Vector2=site.get("position",Vector2.ZERO)
        var cache:=Node3D.new();cache.name="HiddenCache_%s"%str(site.get("name","Cache")).validate_node_name();add_child(cache)
        cache.global_position=_ground(Vector3(point.x,0.0,point.y))
        _service_box(cache,Vector3(0,.25,0),Vector3(1.15,.48,.72),Color(.17,.085,.035))
        var lid:=Node3D.new();lid.name="CacheLid";lid.position=Vector3(0,.50,.34);cache.add_child(lid)
        _service_box(lid,Vector3(0,0,-.34),Vector3(1.18,.16,.74),Color(.22,.11,.045))
        for x in [-.42,.42]:_service_box(cache,Vector3(x,.30,-.37),Vector3(.08,.58,.05),Color(.31,.27,.18))
        _set_geometry_range(cache,95.0)
        _interactables.append({
            "action":"hidden_cache","position":cache.global_position,"radius":2.7,
            "label":"Search concealed cache","node":cache,"lid":lid,"active":true,
            "secret_key":secret_key,"loot_table":site.get("loot_table","frontier_cache"),"name":site.get("name","Hidden Cache"),
        })


func _lore_entry_text(entry:String)->String:
    match entry:
        "pinewatch_muster":
            return "The seventeenth Pinewatch muster records thirty-two wardens at the pass and only eleven returning after the crown's winter summons. The final line was added in another hand:\n\n[i]Do not follow the blue fire beyond Crownfall. It wears the king's voice, but leaves no tracks in snow.[/i]"
        "first_thaw":
            return "Before Crownspire raised its walls, the first road followed this meltwater south. The tablet names the river a covenant: the White Crown keeps the winter, the valley carries its water, and the lowlands feed the realm. Whoever dams one part breaks all three."
        "icewatch_ledger":
            return "Day forty-one. The Rimewater still runs beneath the shelf ice, but the moraine trolls have crossed the blue markers. We relit Icewatch and barred the upper pass. Any expedition continuing north must carry fire, rope, and enough iron to return by a different road."
        "frostline_notes":
            return "Refuge rule: one bundle of split pine for every traveler, two for any party coming down from the Crown. Keep the eastern window clear. Rimefall mist freezes the latch before midnight, and the blue lights on the ridge are not signal lanterns."
        "last_glacial_survey":
            return "The observatory's final survey marks a hollow beneath Crown Glacier. The old astronomers called it the Blue Maw. Their compass needles turned toward the ice instead of north, and their last page records a second crown buried where no king could wear it."
        "last_light_order":
            return "Survey order seven: rope teams leave Last Light at dawn, follow the cairns to Rimefall, and return before the western wall loses the sun. No one crosses the Glacier Sentinel alone. Any crystal recovered from the blue ice belongs first to the refuge stores."
        "oakrest_ledger":
            return "Realmway ledger, rain-month seventeen. Oakrest sent twelve timber carts east and received only seven empty wagons back. The missing teams all crossed Warden's Span after the abbey bell sounded. Maelin has barred night traffic until someone follows the river road and returns with names."
        "rainward_abbey":
            return "The bell was not cast for worship. Its bronze bears flood marks and the old river oath: one toll for a safe ford, two for water over the lower stones, three when no road west remains. The final line is cut by a newer hand: [i]It rang three times beneath a clear sky.[/i]"
        "galehorn_watch":
            return "Galehorn Watch, last signal report. Rainhaven lantern answered at dusk. Stonecross answered at moonrise. The western coast gave no light. Something moved below the ridge in a line too straight for wolves and too quiet for soldiers. I have sent the bell key to the abbey reliquary."
        "stormward_compact":
            return "The Stormward Compact binds three roads and no throne: Greyfen keeps the east cairns, Galehorn keeps the southern descent, and Stormbreak keeps the beacon between them. If one light fails, no caravan crosses the high moor after dusk. The newest line is written in rain-bled ink: [i]Stormscar is dark, but someone still answers it.[/i]"
        "shattered_choir":
            return "We did not sing for the king. We sang so the mountains would return his thunder empty. On the seventh night the buried crown answered from beneath Blacktarn, and every compass in the choir turned north-west. Break the hymn in two. Hide one half with the beacon and one below the nave."
        "blacktarn_notes":
            return "Survey day nine. Blacktarn is fed by snow, rain, and a warmer current beneath the slate. Galehorn Run leaves the basin at a lawful grade, but the needle points into the headwall instead of downriver. We found boot prints ending at open water and none returning."
        "frostharbor_tides":
            return "Frostharbor tide ledger, grey-month twenty-three. Seven boats returned before the western bell. The eighth drifted through Skeldmouth with every net neatly folded and no hands aboard. The harbor chain stays raised after dusk until Cape Keld shows two lights: one for the channel, one for whatever follows beneath it."
        "cape_keld_light":
            return "This light is not a welcome. The first lens faces the sea road so sailors may live. The second faces straight down through the lantern floor. Keep both flames until dawn. If the lower glass turns black, ring Frostharbor once and leave the cape without looking west."
        "whalebone_canticle":
            return "The whale carried winter beneath the waves and laid its ribs upon Keld so the living might shelter inside them. Bone remembers every current. Glass remembers every star. When the drowned crown rises, light the cape, close the harbor, and sing no king's name into the western wind."
        "dawnford_ledger":
            return "Dawnford toll ledger, ember-month twelve. Every wagon bound for March Keep paid in grain, iron, or one hour repairing the realmroad. The final caravan carried no seal and cast no shadow at noon. Tollmaster Vey barred it. By morning his gate stood open and the ash on its wheels pointed east against the wind."
        "ember_span_oath":
            return "Let the Emberwash pass unchained beneath this span. Let the road cross once and honestly. Dawnford keeps the western stone; March Keep keeps the eastern. If the beacon burns three fires, close the bridge and seek the two witnesses before any crown commands passage."
        "cinderwatch_record":
            return "Beacon record, night of red rain. One flame for a clear Dawnway. Two for ash storm. Three for the thing beneath Embercrag. We lit three, but March Keep answered with one. At dawn we found fresh tool marks below the signal vault and basilisk scales warm enough to bend iron."
        _:
            return "Weather and war have erased most of this record. A repeated crest links it to the broken royal road and the old wardens of Crownspire."


func _open_hidden_cache(data:Dictionary)->void:
    data.active=false
    _quest_claimed[str(data.get("secret_key","secret_cache"))]=true
    var lid:=data.get("lid") as Node3D
    if is_instance_valid(lid):create_tween().tween_property(lid,"rotation:x",-1.08,.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    var position:Vector3=data.get("position",player.global_position)
    var table:=str(data.get("loot_table","frontier_cache"))
    if str(profile.get("zone_id",""))=="western_reaches":
        _gathered_counts.rainward_secrets=int(_gathered_counts.get("rainward_secrets",0))+1
    elif str(profile.get("zone_id",""))=="stormbreak_highlands":
        _gathered_counts.stormbreak_secrets=int(_gathered_counts.get("stormbreak_secrets",0))+1
    elif str(profile.get("zone_id",""))=="skeld_coast":
        _gathered_counts.skeld_secrets=int(_gathered_counts.get("skeld_secrets",0))+1
    elif str(profile.get("zone_id",""))=="east_marches":
        _gathered_counts.marcher_secrets=int(_gathered_counts.get("marcher_secrets",0))+1
    _spawn_world_drop(position+Vector3(.55,0,.25),{"kind":"gold","amount":48,"name":"Hidden Crown Coins"},true)
    if table=="white_crown_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"rimefinder_signet","name":"Rimefinder Signet","slot":"ring_left","visual":"magic ring","ring_design":"crown","effect":"frostward","icon":10,
            "armor":4,"hp":18,"mana":6,"power":4,"max_durability":150.0,
            "description":"A hidden Warden signet. Frostward reduces incoming damage while its pale ward circles the wearer.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"crystal","amount":2,"name":"Rime Crystal"},true)
    elif table=="glacial_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"aurora_surveyor_band","name":"Aurora Surveyor Band","slot":"ring_right","visual":"magic ring","ring_design":"spiral","effect":"windstep","icon":10,
            "armor":3,"hp":14,"mana":12,"power":7,"max_durability":180.0,
            "description":"The last surveyor's compass-ring. Its moving green ward quickens travel through the high passes.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"crystal","amount":4,"name":"Aurora Crystal"},true)
    elif table=="glacial_supplies":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"crystal","amount":2,"name":"Rime Crystal"},true)
        _spawn_world_drop(position+Vector3(.16,0,-.56),{"kind":"material","material":"resin","amount":4,"name":"Expedition Fire Resin"},false)
        _spawn_world_drop(position+Vector3(.62,0,-.18),{
            "kind":"item","id":"rimefall_trail_ration","stack_key":"item:rimefall_trail_ration","stackable":true,"quantity":2,
            "name":"Rimefall Trail Ration","slot":"consumable","icon":10,"use":"food","buff_name":"Warm March","duration":240.0,
            "buff_power":4,"health_regen":.28,"stamina_regen":3.0,"heal":22.0,
            "description":"Two wax-wrapped expedition rations that restore health and steady stamina in the high pass.",
        },false)
    elif table=="blue_maw_hoard":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"blue_maw_cleaver","name":"Blue Maw Cleaver","slot":"mainhand","visual":"sword","icon":7,
            "armor":0,"hp":12,"mana":0,"power":24,"max_durability":210.0,
            "description":"A broad troll-forged blade with glacial iron along its edge.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"ore","amount":7,"name":"Glacial Iron"},true)
    elif table=="marcher_supplies":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"ore","amount":5,"name":"Dawnway Basalt Iron"},true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"resin","amount":4,"name":"Caravan Wheel Pitch"},false)
        _spawn_world_drop(position+Vector3(.50,0,-.12),{
            "kind":"item","id":"amberfield_waybread","stack_key":"item:amberfield_waybread","stackable":true,"quantity":2,
            "name":"Amberfield Waybread","slot":"consumable","icon":10,"use":"food","buff_name":"Long Road","duration":270.0,
            "buff_power":4,"health_regen":.25,"stamina_regen":4.0,"heal":20.0,
            "description":"Two dense loaves baked for the Dawnway caravans. Restores health and steadies stamina.",
        },false)
    elif table=="marcher_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"barrow_witness_band","name":"Barrow Witness Band","slot":"ring_left","visual":"magic ring","ring_design":"crown","effect":"emberpulse","icon":10,
            "armor":4,"hp":16,"mana":7,"power":9,"max_durability":195.0,
            "description":"The eastern witness seal in basalt iron and old amber. A warm oath-mark circles its setting.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"essence","amount":3,"name":"Barrow Oath Ember"},true)
    elif table=="cinderwatch_gear":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"cinderwatch_scale_jack","name":"Cinderwatch Scale Jack","slot":"chest","visual":"chest","icon":1,
            "armor":22,"hp":32,"mana":0,"power":6,"max_durability":220.0,
            "description":"Basalt-iron lamellae backed with heat-cured leather from the beacon survey stores.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"crystal","amount":3,"name":"Emberglass"},true)
    elif table=="rainward_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"abbots_tideglass_signet","name":"Abbot's Tideglass Signet","slot":"ring_left","visual":"magic ring","ring_design":"split_band","effect":"windstep","icon":10,
            "armor":4,"hp":16,"mana":8,"power":7,"max_durability":175.0,
            "description":"Rainfall glass set in the abbey's broken silver seal. A green-blue current circles the wearer.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"crystal","amount":3,"name":"Rainfall Glass"},true)
    elif table=="warden_supplies":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"galehorn_patrol_cloak","name":"Galehorn Patrol Cloak","slot":"shoulders","visual":"shoulders","icon":2,
            "armor":8,"hp":20,"mana":0,"power":4,"max_durability":160.0,
            "description":"A waxed green patrol cloak carrying Galehorn's small silver bell clasp.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"resin","amount":5,"name":"Warden's Waxed Resin"},false)
    elif table=="rainhaven_trade":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"cloth","amount":5,"name":"Rainhaven Sailcloth"},false)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"resin","amount":4,"name":"Riverboat Pitch"},false)
    elif table=="stormbreak_beacon":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"stormscar_keeper_mantle","name":"Stormscar Keeper Mantle","slot":"shoulders","visual":"shoulders","effect":"windstep","icon":2,
            "armor":10,"hp":22,"mana":0,"power":6,"max_durability":190.0,
            "description":"A slate-grey beacon mantle pinned with a black-iron flame. Its ward parts the high wind around the wearer.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"ore","amount":6,"name":"Stormscar Iron"},true)
    elif table=="stormbreak_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"tempest_choir_band","name":"Tempest Choir Band","slot":"ring_right","visual":"magic ring","ring_design":"spiral","effect":"windstep","icon":10,
            "armor":5,"hp":18,"mana":12,"power":9,"max_durability":205.0,
            "description":"Two joined silver hymn-lines turn around a core of Blacktarn glass, leaving a visible storm-blue wake.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"essence","amount":3,"name":"Choir Resonance"},true)
    elif table=="stormbreak_supplies":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"resin","amount":5,"name":"Highland Fire Resin"},false)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"cloth","amount":5,"name":"Storm Wool"},false)
    elif table=="skeld_lighthouse":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"cape_keld_watchcoat","name":"Cape Keld Watchcoat","slot":"chest","visual":"chest","effect":"frostward","icon":1,
            "armor":17,"hp":36,"mana":6,"power":5,"max_durability":225.0,
            "description":"Salt-dark hide and storm wool worn by Cape Keld's missing keeper. Its pale ward strengthens in cold spray.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"crystal","amount":4,"name":"Lantern Sea-Glass"},true)
    elif table=="skeld_relics":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{
            "kind":"item","id":"greywake_lantern_band","name":"Greywake Lantern Band","slot":"ring_left","visual":"magic ring","ring_design":"split_band","effect":"frostward","icon":10,
            "armor":5,"hp":18,"mana":14,"power":9,"max_durability":220.0,
            "description":"The chapel's lower lantern in miniature. Cold green light follows its sea-glass setting.",
        },true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"essence","amount":4,"name":"Whalebone Memory"},true)
    elif table=="skeld_supplies":
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"ore","amount":7,"name":"Vardholm Saltsteel"},true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"resin","amount":5,"name":"Tarred Net Pitch"},false)
        _spawn_world_drop(position+Vector3(.50,0,-.15),{
            "kind":"item","id":"skeld_smoked_fish","stack_key":"item:skeld_smoked_fish","stackable":true,"quantity":2,
            "name":"Skeld Smoked Fish","slot":"consumable","icon":10,"use":"food","buff_name":"Sea Legs","duration":300.0,
            "buff_power":5,"health_regen":.34,"stamina_regen":4.2,"heal":26.0,
            "description":"Two strips of juniper-smoked fish. Restores health and steadies stamina for a long coastal march.",
        },false)
    else:
        _spawn_world_drop(position+Vector3(-.48,0,.20),{"kind":"material","material":"ore","amount":5,"name":"Greyfen Ore"},true)
        _spawn_world_drop(position+Vector3(0,0,-.55),{"kind":"material","material":"essence","amount":2,"name":"Smuggled Essence"},true)
    _check_quest_rewards()
    _notify("Secret found: %s"%data.get("name","Hidden Cache"),Color(.72,.92,1.0))


func _scale_latest_region_enemy(rank:int)->void:
    if minions.is_empty():return
    var enemy:Dictionary=minions[-1]
    var base_rank:=maxi(1,int(enemy.get("rank",1)))
    var difficulty:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    var rank_factor:=1.0+float(maxi(0,rank-base_rank))*.16
    var factor:=difficulty*rank_factor
    enemy["rank"]=maxi(base_rank,rank)
    enemy["hp"]=float(enemy.get("hp",40.0))*factor
    if enemy.has("max_hp"):enemy["max_hp"]=float(enemy.get("max_hp",enemy.hp))*factor
    if enemy.has("attack_damage"):enemy["attack_damage"]=float(enemy.attack_damage)*(1.0+(factor-1.0)*.62)


func _profile_configure_step(label:String,total_start_usec:int,step_start_usec:int)->void:
    if OS.get_environment("BROKEN_KNIGHT_PROFILE_BUILD")!="1":return
    var now_usec:int=Time.get_ticks_usec()
    print("GAMEPLAY_CONFIG_PROFILE|%s|step_ms=%.1f|total_ms=%.1f"%[
        label,float(now_usec-step_start_usec)/1000.0,float(now_usec-total_start_usec)/1000.0,
    ])


func clear_for_zone_reload(preserve_mount:bool=false)->void:
    # Outdoor streamed regions share the same player and mount nodes. Forcing a
    # dismount here made crossing the north preparation line look like the
    # horse had thrown the player. Hard portal reloads keep the old behaviour.
    if not preserve_mount and is_instance_valid(player) and player.has_method("is_mounted") and player.is_mounted():player.dismount_horse()
    for child in get_children():child.free()
    minions.clear();projectiles.clear();loot.clear();_vendors.clear();_portals.clear();_interactables.clear()
    _nearby_portal={};_nearby_interactable={};_nearby_loot={};nearby_vendor_data={};nearby_vendor=""
    _forest_trees.clear();_tree_buckets.clear();_nearby_world_tree={}
    _mineable_rocks.clear();_mineable_rock_buckets.clear();_nearby_world_rock={}
    _fishing_active=false;_fishing_phase="";_fishing_timer=0.0;_fishing_spot={};_fishing_elapsed=0.0
    _fishing_visual=null;_fishing_bobber=null;_fishing_line=null;_fishing_ripple=null;_fishing_fish_shadow=null
    _local_prop_collision_shapes.clear();_rock_collision_registry.clear();_prop_collision_buckets.clear();_local_prop_collision_body=null
    _active_prop_collision_slots.clear();_prop_collision_slot_keys.clear()
    _stream_transition_queue.clear()
    _last_stream_transition={}
    _last_collision_refresh={}
    _service_material_cache.clear();_spawn_count=0
    _gravebound_campaign=null
    _oathbound_campaign=null
    _player_campfires.clear()
    _townfolk.clear()


func get_zone_transition_state()->Dictionary:
    return {
        "quest_complete":quest_complete,
        "quest_goal":quest_goal,
        "quest_claimed":_quest_claimed.duplicate(true),
        "quest_baselines":_quest_baselines.duplicate(true),
        "gathered_counts":_gathered_counts.duplicate(true),
        "gravebound_campaign":_gravebound_campaign.get_save_state() if is_instance_valid(_gravebound_campaign) else {},
        "oathbound_campaign":_oathbound_campaign.get_save_state() if is_instance_valid(_oathbound_campaign) else {},
    }


func load_zone_transition_state(data:Dictionary)->void:
    quest_complete=bool(data.get("quest_complete",quest_complete))
    quest_goal=maxi(1,int(data.get("quest_goal",quest_goal)))
    _quest_claimed=data.get("quest_claimed",_quest_claimed).duplicate(true)
    _quest_baselines=data.get("quest_baselines",_quest_baselines).duplicate(true)
    _gathered_counts.merge(data.get("gathered_counts",{}),true)
    if is_instance_valid(_gravebound_campaign):_gravebound_campaign.load_save_state(data.get("gravebound_campaign",{}))
    if is_instance_valid(_oathbound_campaign):_oathbound_campaign.load_save_state(data.get("oathbound_campaign",{}))


func _build_zone_exits()->void:
    var margin:=float(profile.get("world_size",7200.0))*.465
    var region_origin:Vector2=profile.get("region_origin",Vector2.ZERO)
    for exit_data in profile.get("zone_exits",[]):
        # Seamless outdoor regions are crossed in-world. A portal arch and E
        # prompt would expose the streaming boundary and duplicate the road.
        if bool(exit_data.get("seamless",false)):continue
        var edge:String=exit_data.get("edge","north")
        var point:=Vector2(0,-margin)
        if edge=="north":point=Vector2(0,margin)
        elif edge=="east":point=Vector2(margin,0)
        elif edge=="west":point=Vector2(-margin,0)
        point+=region_origin
        var gate:=Node3D.new();gate.name="ZoneGate_%s"%edge.capitalize();add_child(gate);gate.global_position=_ground(Vector3(point.x,0,point.y))
        var stone:=Color(.42,.43,.40)
        for side in [-1.0,1.0]:_service_solid_box(gate,Vector3(side*4.0,3.2,0),Vector3(1.4,6.4,1.8),stone)
        _service_solid_box(gate,Vector3(0,6.15,0),Vector3(9.2,1.4,1.8),stone)
        var marker:=Label3D.new();marker.text="ROAD TO %s\nE - TRAVEL TO NEW ZONE"%str(exit_data.get("target","frontier")).replace("_"," ").to_upper();marker.position=Vector3(0,8.1,0);marker.font_size=30;marker.pixel_size=.012;marker.modulate=Color(1,.79,.34);marker.outline_size=8;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;gate.add_child(marker)
        _portals.append({"action":"zone_travel","position":gate.global_position,"radius":7.5,"label":"Travel to %s"%str(exit_data.get("target","frontier")).replace("_"," ").capitalize(),"target":exit_data.get("target","starting_realm"),"entry":exit_data.get("entry","south")})

func _process(delta: float) -> void:
    if not is_instance_valid(player): return
    _stream_transition_frame=(_stream_transition_frame+1)%4
    if _stream_transition_frame==0:_apply_stream_transitions(1)
    if not (player.has_method("is_warrior") and player.is_warrior()):
        player.mana = minf(player.max_mana, player.mana + 2.2 * delta)
    for i in range(4): cooldowns[i] = maxf(0.0, cooldowns[i] - delta)

    if Input.is_key_pressed(KEY_5): player.use_health_potion()
    if Input.is_key_pressed(KEY_6): player.use_mana_potion()
    _tick_projectiles(delta)
    _minion_tick_accumulator += delta
    if _minion_tick_accumulator >= 1.0 / 30.0:
        var minion_delta := minf(_minion_tick_accumulator, 0.08)
        _minion_tick_accumulator = 0.0
        _tick_minions(minion_delta)
    _tick_loot(delta)
    _tick_fishing(delta)
    _townfolk_tick_accumulator+=delta
    if _townfolk_tick_accumulator>=.10:
        var townfolk_delta:=minf(_townfolk_tick_accumulator,.24)
        _townfolk_tick_accumulator=0.0
        _tick_townfolk(townfolk_delta)
    _portal_cooldown = maxf(0.0, _portal_cooldown - delta)
    _tick_auto_portal()
    _magic_requirement_time = maxf(0.0,_magic_requirement_time-delta)
    _vendor_scan_cooldown -= delta
    if _vendor_scan_cooldown <= 0.0:
        _vendor_scan_cooldown = 0.10
        _tick_vendor()
    _stream_tick+=delta
    _collision_refresh_tick+=delta
    if _collision_refresh_tick>=.08:
        _collision_refresh_tick=0.0
        _refresh_local_prop_collisions()
    if _stream_tick>=.35:
        _stream_tick=0.0
        _stream_local_gameplay()

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo): return

    if event.keycode >= KEY_1 and event.keycode <= KEY_4:
        if not is_instance_valid(player):
            return

        if player.has_method("is_warrior") and player.is_warrior():
            match event.keycode:
                KEY_1: _warrior_sword_slash()
                KEY_2: _warrior_shield_bash()
                KEY_3: _warrior_charge()
                KEY_4: _warrior_war_cry()
        else:
            match event.keycode:
                KEY_1: _cast_spark()
                KEY_2: _cast_nova()
                KEY_3: _cast_blink()
                KEY_4: _cast_orb()

        get_viewport().set_input_as_handled()
        return
    if event.keycode == KEY_F3: for i in range(5): _spawn_minion(16.0 + i * 5.0, float(i))
    elif event.keycode == KEY_F4: _clear_minions()
    elif event.keycode == KEY_F5: player.hp = player.max_hp; player.mana = player.max_mana
    elif event.keycode == KEY_F6: player.global_position = _ground(player.get("_spawn_position"))
    elif event.keycode == KEY_F9: _save_game()
    elif event.keycode == KEY_F10: _load_game()
    elif event.keycode == KEY_E:
        if is_instance_valid(player) and player.has_method("is_mounted") and player.is_mounted():
            player.dismount_horse()
            _refresh_horse_interaction_states()
            _notify("Dismounted — press E beside the horse to ride again",Color(.86,.75,.48))
            get_viewport().set_input_as_handled()
            return
        if _fishing_active:
            _reel_fishing()
            get_viewport().set_input_as_handled()
            return
        # Resolve every interaction again on the key press. A quick tap after
        # reaching a tree should not depend on the slower HUD proximity scan.
        _tick_vendor()
        var pressed_portal:=_find_available_portal()
        if not pressed_portal.is_empty():
            _activate_portal(pressed_portal)
        elif not _nearby_interactable.is_empty():
            _activate_interactable(_nearby_interactable)
        elif not _nearby_world_tree.is_empty():
            _activate_world_tree(_nearby_world_tree)
        elif not _nearby_world_rock.is_empty():
            _activate_world_rock(_nearby_world_rock)
        elif not _nearby_loot.is_empty():
            _collect_nearby_loot()
        elif not nearby_vendor_data.is_empty():
            vendor_requested.emit(nearby_vendor_data)

func get_minion_positions() -> Array[Vector3]:
    var result: Array[Vector3] = []
    for m in minions:
        if is_instance_valid(m.node) and not m.get("dead", false): result.append(m.node.global_position)
    return result


func get_world_interaction_markers()->Array[Dictionary]:
    var result:Array[Dictionary]=[]
    for interaction in _interactables:
        if not interaction.get("active",true):continue
        result.append({"position":interaction.get("position",Vector3.ZERO),"action":interaction.get("action","")})
    return result


func get_story_map_markers()->Array[Dictionary]:
    var result:Array[Dictionary]=[]
    if is_instance_valid(_oathbound_campaign) and _oathbound_campaign.has_method("get_map_markers"):
        result.append_array(_oathbound_campaign.get_map_markers())
    if is_instance_valid(_gravebound_campaign) and _gravebound_campaign.has_method("get_map_markers"):
        result.append_array(_gravebound_campaign.get_map_markers())
    return result


func get_map_service_markers()->Array[Dictionary]:
    # The royal survey is intentionally complete: services are mapped whether
    # or not the player has visited their town yet.
    var result:Array[Dictionary]=[]
    for vendor in _vendors:
        if not is_instance_valid(vendor) or not vendor.has_meta("vendor_data"):continue
        var data:Dictionary=vendor.get_meta("vendor_data")
        result.append({
            "kind":"vendor",
            "name":"%s — %s"%[str(data.get("name","Merchant")),str(data.get("type_name","Vendor"))],
            "position":vendor.global_position,
        })
    return result

func get_cooldowns() -> Array: return cooldowns

func get_gameplay_state() -> Dictionary:
    var interaction:="Equip the Royal Vanguard Staff to cast magic." if _magic_requirement_time>0.0 else nearby_vendor
    var quests:=get_quest_state()
    var active:Dictionary={}
    for quest in quests:
        if bool(quest.get("available",true)) and not bool(quest.get("claimed",false)):
            active=quest
            break
    if active.is_empty() and not quests.is_empty():active=quests[0]
    var defeated:int=int(player.enemies_defeated) if is_instance_valid(player) else 0
    return {"quest":active.get("title",quest_title),"quest_description":active.get("description",""),"quest_current":active.get("current",mini(defeated,quest_goal)),"quest_goal":active.get("goal",quest_goal),"quest_complete":active.get("complete",quest_complete),"quests":quests,"loot":loot.size(),"minions":minions.size(),"interaction":interaction}

func get_skill_state() -> Dictionary:
    var upgrades:=[]
    for i in range(4):upgrades.append(_skill_upgrade_summary(i,skill_levels[i]))
    var names:=["Sword Slash","Shield Bash","Vanguard Charge","War Cry"] if is_instance_valid(player) and player.has_method("is_warrior") and player.is_warrior() else ["Spark","Nova","Blink","Orb"]
    return {"names":names,"levels":skill_levels,"xp":skill_xp,"upgrades":upgrades}

func get_max_cooldowns()->Array:
    if is_instance_valid(player) and player.has_method("is_warrior") and player.is_warrior():return [.80,1.15,2.4,5.5]
    return [maxf(.14,.22-float(skill_levels[0]-1)*.004),maxf(1.15,1.8-float(skill_levels[1]-1)*.035),maxf(1.65,2.8-float(skill_levels[2]-1)*.055),maxf(2.15,3.4-float(skill_levels[3]-1)*.06)]

func _require_warrior_weapons()->bool:
    return is_instance_valid(player) and player.has_method("has_warrior_weapons_equipped") and player.has_warrior_weapons_equipped()

func _warrior_sword_slash()->void:
    if not _require_warrior_weapons() or cooldowns[0]>0.0 or player.stamina<12.0:return
    player.stamina-=12.0
    player.damage_equipment("mainhand",.55)
    cooldowns[0]=.80;_hero_action("sword")
    await get_tree().create_timer(.23).timeout
    if not is_instance_valid(player):return
    _damage_cone(4.2,1.15,28.0+float(player.get_equipment_state().get("power",0))*.55,6.0)

func _warrior_shield_bash()->void:
    if not _require_warrior_weapons() or cooldowns[1]>0.0 or player.stamina<20.0:return
    player.stamina-=20.0
    player.damage_equipment("offhand",.72)
    cooldowns[1]=1.15;_hero_action("shield")
    _damage_cone(3.2,.88,18.0+float(player.get_equipment_state().get("power",0))*.32,13.0)
    _burst(player.global_position+_combat_forward()*1.3,Color(.35,.58,1.0),2.2)

func _warrior_charge()->void:
    if not _require_warrior_weapons() or cooldowns[2]>0.0 or player.stamina<28.0:return
    player.stamina-=28.0
    player.damage_equipment("mainhand",.86)
    cooldowns[2]=2.4;_hero_action("charge")
    var start:=player.global_position;var direction:=_combat_forward();var target:=start+direction*7.5
    if not walkable_sampler.is_valid() or walkable_sampler.call(target.x,target.z):player.global_position=_ground(target)
    _damage_cone(5.5,1.55,36.0,16.0)

func _warrior_war_cry()->void:
    if not _require_warrior_weapons() or cooldowns[3]>0.0 or player.stamina<35.0:return
    player.stamina-=35.0
    cooldowns[3]=5.5;_hero_action("warcry");player.hp=minf(player.max_hp,player.hp+16.0)
    _burst(player.global_position,Color(1.0,.48,.10),9.0)
    _damage_area(player.global_position,8.5,22.0,Color(1.0,.38,.08))

func _damage_cone(range_distance:float,half_angle:float,damage:float,knockback_strength:float)->void:
    var forward:=_combat_forward()
    for m in minions:
        if not is_instance_valid(m.node) or m.get("dead",false):continue
        var offset:Vector3=m.node.global_position-player.global_position;offset.y=0.0
        if offset.length()<=range_distance and forward.dot(offset.normalized())>=cos(half_angle):
            _damage(m,damage,offset.normalized()*knockback_strength)

func _skill_upgrade_summary(index:int,level:int)->String:
    match index:
        0:return "Triple piercing spread" if level>=10 else ("Twin-bolt spread" if level>=5 else "Focused bolt")
        1:return "Wide lingering shockwave" if level>=10 else ("Slowing shockwave" if level>=5 else "Close shock ring")
        2:return "Blink landing burst" if level>=10 else ("Long river blink" if level>=5 else "Short blink")
        3:return "Piercing burst orb" if level>=10 else ("Piercing orb" if level>=5 else "Arcane orb")
    return ""

func _gain_skill(i:int,amount:int)->void:
    skill_xp[i]+=amount
    while skill_xp[i]>=skill_levels[i]*8:
        skill_xp[i]-=skill_levels[i]*8
        skill_levels[i]+=1
        _burst(player.global_position,Color(1.0,.78,.28),2.4)

func _cast_spark() -> void:
    if not _require_magic_staff():return
    if cooldowns[0] > 0 or player.mana < 8: return
    var level:int=skill_levels[0]
    cooldowns[0] = get_max_cooldowns()[0]; player.mana -= 8; _hero_action("spark")
    _gain_skill(0,1)
    var damage:=13.0*(1.0+float(level-1)*.085)
    var speed:=24.0+minf(5.0,float(level-1)*.45)
    var angles:Array=[0.0]
    if level>=10:angles=[-.18,0.0,.18]
    elif level>=5:angles=[-.09,.09]
    var base_dir:=_assisted_aim(_cast_origin(),36.0)
    for i in range(angles.size()):
        var shot_dir:=Basis(Vector3.UP,float(angles[i]))*base_dir
        _projectile(Color(0.40,0.86,1.0),speed,damage,1.5+.10*float(level>=10),.18,shot_dir,1 if level>=10 else 0,0.0,i==angles.size()/2)

func _cast_nova() -> void:
    if not _require_magic_staff():return
    if cooldowns[1] > 0 or player.mana < 18: return
    var level:int=skill_levels[1]
    cooldowns[1] = get_max_cooldowns()[1]; player.mana -= 18; _hero_action("nova")
    _gain_skill(1,2)
    var radius:=14.0 if level>=10 else (11.8 if level>=5 else 10.0)
    var damage:=20.0*(1.0+float(level-1)*.075)
    _burst(player.global_position, Color(0.72,0.94,1), radius)
    for m in minions:
        if is_instance_valid(m.node) and m.node.global_position.distance_to(player.global_position) < radius:
            var push:Vector3=m.node.global_position-player.global_position
            _damage(m,damage,push.normalized() if push.length_squared()>.001 else Vector3.FORWARD)

func _cast_blink() -> void:
    if not _require_magic_staff():return
    if cooldowns[2] > 0 or player.mana < 14: return
    var level:int=skill_levels[2]
    cooldowns[2] = get_max_cooldowns()[2]; player.mana -= 14; _hero_action("blink")
    _gain_skill(2,2)
    var dir := _combat_forward()
    var start:=player.global_position
    var distance:=26.0 if level>=10 else (22.0 if level>=5 else 18.0+minf(3.0,float(level-1)*.6))
    var target: Vector3 = player.global_position + dir * distance
    var can_land:bool=not walkable_sampler.is_valid() or bool(walkable_sampler.call(target.x,target.z))
    if can_land:
        if level<5:
            for step in range(1,6):
                var probe:=start+dir*distance*(float(step)/5.0)
                if walkable_sampler.is_valid() and not walkable_sampler.call(probe.x,probe.z):can_land=false;break
        if can_land:
            player.global_position=Vector3(target.x,start.y,target.z) if bool(player.get("_interior_mode")) else _ground(target)
    _blink_sparkles(start,player.global_position)
    if level>=10 and can_land:_damage_area(player.global_position,7.0,18.0+float(level)*1.5,Color(1,.76,.25))

func _blink_sparkles(start:Vector3,finish:Vector3)->void:
    var color:=Color(1.0,.72,.16)
    for i in range(20):
        var sparkle:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=.035+float(i%3)*.014;mesh.height=mesh.radius*2.0;sparkle.mesh=mesh
        var material:=StandardMaterial3D.new();material.albedo_color=color;material.emission_enabled=true;material.emission=color;material.emission_energy_multiplier=4.5;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;sparkle.material_override=material;add_child(sparkle)
        var t:=float(i)/19.0;var side:=Vector3(sin(float(i)*2.3),cos(float(i)*1.7),sin(float(i)*.9))*.32
        sparkle.global_position=start.lerp(finish,t)+Vector3.UP*(.35+sin(t*PI)*.8)+side
        var tween:=create_tween();tween.tween_property(sparkle,"scale",Vector3.ONE*(2.0+float(i%4)*.25),.10);tween.tween_property(sparkle,"scale",Vector3.ZERO,.22);tween.tween_callback(sparkle.queue_free)

func _cast_orb() -> void:
    if not _require_magic_staff():return
    if cooldowns[3] > 0 or player.mana < 22: return
    var level:int=skill_levels[3]
    cooldowns[3] = get_max_cooldowns()[3]; player.mana -= 22; _hero_action("orb")
    _gain_skill(3,2)
    var damage:=34.0*(1.0+float(level-1)*.09)
    _projectile(Color(0.70,0.38,1),13.0+minf(4.0,float(level-1)*.35),damage,3.4+.18*float(level>=5),.42+(.06 if level>=5 else 0.0),Vector3.ZERO,2 if level>=10 else (1 if level>=5 else 0),7.2 if level>=10 else 0.0)

func _require_magic_staff()->bool:
    if is_instance_valid(player) and player.has_method("has_magic_staff_equipped") and player.has_magic_staff_equipped():return true
    _magic_requirement_time=2.2
    return false

func _projectile(color: Color, speed: float, damage: float, life: float, radius: float, direction_override:Vector3=Vector3.ZERO, pierce:int=0, burst_radius:float=0.0, with_light:bool=true) -> void:
    var mesh := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = radius; sphere.height = radius * 2.0; mesh.mesh = sphere
    var mat := StandardMaterial3D.new(); mat.albedo_color = color; mat.emission_enabled = true; mat.emission = color; mat.emission_energy_multiplier = 3.0; mesh.material_override = mat
    add_child(mesh)
    var origin := _cast_origin()
    var dir := direction_override.normalized() if direction_override.length_squared()>.001 else _assisted_aim(origin, 34.0 if speed > 20.0 else 27.0)
    mesh.global_position = origin
    if with_light:
        var glow:=OmniLight3D.new();glow.light_color=color;glow.light_energy=1.0;glow.omni_range=3.2;glow.shadow_enabled=false;mesh.add_child(glow)
    var halo:=MeshInstance3D.new();var halo_mesh:=SphereMesh.new();halo_mesh.radius=radius*1.8;halo_mesh.height=radius*3.6;halo.mesh=halo_mesh
    var halo_mat:=StandardMaterial3D.new();halo_mat.albedo_color=Color(color.r,color.g,color.b,.16);halo_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;halo_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;halo.material_override=halo_mat;mesh.add_child(halo)
    var tail:=MeshInstance3D.new();var tail_mesh:=CylinderMesh.new();tail_mesh.top_radius=radius*.18;tail_mesh.bottom_radius=radius*.62;tail_mesh.height=radius*5.0;tail.mesh=tail_mesh
    var tail_mat:=StandardMaterial3D.new();tail_mat.albedo_color=Color(color.r,color.g,color.b,.52);tail_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;tail_mat.emission_enabled=true;tail_mat.emission=color;tail_mat.emission_energy_multiplier=2.2;tail.material_override=tail_mat
    tail.quaternion=Quaternion(Vector3.UP,dir);tail.position=-dir*radius*2.4;mesh.add_child(tail)
    _cast_flash(origin, color, radius * 3.0)
    projectiles.append({"node":mesh,"dir":dir,"speed":speed,"damage":damage,"life":life,"radius":radius,"color":color,"pierce":pierce,"burst_radius":burst_radius,"hit_ids":[]})

func _tick_projectiles(delta: float) -> void:
    for i in range(projectiles.size()-1, -1, -1):
        var p := projectiles[i]; p.life -= delta
        var start:Vector3=p.node.global_position
        var finish:Vector3=start+p.dir*p.speed*delta
        p.node.global_position=finish
        var hit := false
        for m in minions:
            if not is_instance_valid(m.node):continue
            var target_id:int=m.node.get_instance_id()
            if p.hit_ids.has(target_id):continue
            var target:Vector3=m.node.global_position+Vector3.UP*.7
            if _distance_to_segment_3d(target,start,finish)<1.0+float(p.radius):
                _damage(m,p.damage,p.dir);_impact_flash(target,p.color,float(p.radius));p.hit_ids.append(target_id)
                if int(p.pierce)>0:p.pierce=int(p.pierce)-1
                else:hit=true;break
        if hit or p.life <= 0:
            if not hit:_impact_flash(p.node.global_position,p.color,float(p.radius)*.55)
            if float(p.burst_radius)>0.0:_damage_area(p.node.global_position,float(p.burst_radius),float(p.damage)*.55,p.color,p.hit_ids)
            p.node.queue_free();projectiles.remove_at(i)

func _damage_area(pos:Vector3,radius:float,damage:float,color:Color,excluded:Array=[])->void:
    _burst(_ground(pos),color,radius)
    for m in minions:
        if not is_instance_valid(m.node) or excluded.has(m.node.get_instance_id()):continue
        var offset:Vector3=m.node.global_position-pos
        if offset.length()<=radius:_damage(m,damage,offset.normalized() if offset.length_squared()>.001 else Vector3.FORWARD)

func _spawn_minion(distance: float, angle: float, fixed_position: Variant = null, rank: int = 1, dungeon_bounds: Rect2 = Rect2()) -> void:
    if not is_instance_valid(player): return
    var root := Node3D.new();root.set_meta("always_streamed",true);add_child(root)
    _spawn_count += 1
    var elite := _spawn_count % 5 == 0
    var in_dungeon := fixed_position is Vector3 and dungeon_bounds.has_area()
    root.name = ("Cavern " if rank >= 3 else ("Well " if in_dungeon else "")) + ("Elite Imp" if elite else "Imp")
    var visual := _build_low_cost_imp(elite)
    visual.name = "ImpVisual"
    # Blender's authored front imports opposite Godot's -Z look_at direction.
    visual.rotation.y = PI
    root.add_child(visual)
    var base_scale := .82 if elite else .62
    root.scale = Vector3.ONE * base_scale
    var animation_player := _find_animation_player(visual)
    if animation_player:
        for clip in ["Idle","Run"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
        for clip in ["Attack","Hit","Death"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_NONE
        animation_player.play("Idle")
    var flash_material := StandardMaterial3D.new()
    flash_material.albedo_color = Color(1.0, 0.08, 0.025)
    flash_material.emission_enabled = true
    flash_material.emission = Color(1.0, 0.025, 0.005)
    flash_material.emission_energy_multiplier = 2.8
    flash_material.roughness = 0.7
    if elite:
        _add_elite_imp_effect(root)
    var pos: Vector3
    if fixed_position is Vector3:
        pos = fixed_position
        root.global_position = pos if in_dungeon else _ground(pos)
    else:
        var origin2 := Vector2(player.global_position.x,player.global_position.z)
        if origin2.distance_to(safe_zone_center)<safe_zone_radius:
            distance=maxf(distance,safe_zone_radius+14.0)
        pos=player.global_position+Vector3(cos(angle),0,sin(angle))*distance
        for attempt in range(8):
            if (not walkable_sampler.is_valid() or walkable_sampler.call(pos.x,pos.z)) and not _inside_safe_zone(pos):break
            var retry_angle:=angle+float(attempt+1)*0.73
            var retry_distance:=distance+float(attempt+1)*7.0
            pos=player.global_position+Vector3(cos(retry_angle),0,sin(retry_angle))*retry_distance
        root.global_position=_ground(pos)
    var rank_scale := 1.0 + float(maxi(0, rank - 1)) * 0.72
    minions.append({"node":root,"hp":(90.0 if elite else 38.0)*rank_scale,"phase":rng.randf_range(0,TAU),"attack":0.0,"windup":0.0,"knockback":Vector3.ZERO,"elite":elite,"base_scale":base_scale,"animation":animation_player,"anim_lock":0.0,"flash_time":0.0,"flash_material":flash_material,"dead":false,"death_time":0.0,"dungeon":in_dungeon,"floor_y":root.global_position.y,"bounds":dungeon_bounds,"rank":rank,"kind":"imp"})


func _build_low_cost_imp(elite:bool)->Node3D:
    # The authored Blender imp is consolidated to one skinned mesh at export,
    # so gameplay can use the real rig without the old 81-node draw overhead.
    # Keep the procedural construction below as a defensive fallback only.
    var authored:=IMP_SCENE.instantiate()
    if authored:return authored
    var visual:=Node3D.new()
    var skin:=Color(.52,.075,.032) if not elite else Color(.64,.055,.025)
    var belly:=Color(.76,.17,.045) if not elite else Color(.92,.22,.035)
    var horn:=Color(.15,.095,.065)
    _dragon_part(visual,"Body",Vector3(0,1.05,0),Vector3(.92,1.25,.70),skin)
    _dragon_part(visual,"Head",Vector3(0,1.82,.04),Vector3(.88,.72,.76),skin)
    _dragon_part(visual,"Muzzle",Vector3(0,1.67,.43),Vector3(.55,.30,.42),belly)
    for side in [-1.0,1.0]:
        _dragon_cone(visual,Vector3(side*.30,2.30,.02),.14,.75,horn,Vector3(0,0,side*.38))
        _dragon_part(visual,"Eye",Vector3(side*.20,1.94,.39),Vector3(.13,.13,.10),Color(1.0,.72,.08),true)
        _dragon_part(visual,"Arm",Vector3(side*.56,1.05,.02),Vector3(.23,.88,.23),skin)
        _dragon_part(visual,"Leg",Vector3(side*.24,.36,-.02),Vector3(.27,.72,.29),skin)
        var wing:=_service_box(visual,Vector3(side*.64,1.35,-.30),Vector3(.66,.72,.09),Color(.30,.035,.025))
        wing.rotation.z=side*.48
        wing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _dragon_cone(visual,Vector3(0,.96,-.62),.12,.88,skin,Vector3(PI*.5,0,0))
    return visual

func _spawn_dragon(position:Vector3,rank:int,bounds:Rect2,boss_id:String)->void:
    var root:=Node3D.new();root.name="Cave Dragon Boss";root.set_meta("always_streamed",true);add_child(root);root.global_position=position
    var visual:=DRAGON_SCENE.instantiate() as Node3D
    if not visual:
        push_error("The authored cave dragon failed to instantiate.")
        root.queue_free()
        return
    visual.name="DragonVisual"
    # The Blender dragon is authored facing +Y, which imports facing Godot -Z.
    # Keeping this at zero lets Node3D.look_at face the boss toward the player.
    visual.rotation.y=0.0
    root.add_child(visual)
    var animation_player:=_find_animation_player(visual)
    if animation_player:
        for loop_clip in ["Idle","Walk"]:
            if animation_player.has_animation(loop_clip):
                animation_player.get_animation(loop_clip).loop_mode=Animation.LOOP_LINEAR
        for one_shot_clip in ["Attack","Roar","FireBreath","Death"]:
            if animation_player.has_animation(one_shot_clip):
                animation_player.get_animation(one_shot_clip).loop_mode=Animation.LOOP_NONE
        animation_player.play("Idle")
    var flash:=StandardMaterial3D.new();flash.albedo_color=Color(1,.07,.01);flash.emission_enabled=true;flash.emission=Color(1,.015,.002);flash.emission_energy_multiplier=3.5
    minions.append({"node":root,"hp":2200.0+float(rank)*240.0,"phase":0.0,"attack":1.5,"windup":0.0,"knockback":Vector3.ZERO,"elite":true,"base_scale":1.0,"animation":animation_player,"anim_lock":0.0,"flash_time":0.0,"flash_material":flash,"dead":false,"death_time":0.0,"dungeon":true,"floor_y":position.y,"bounds":bounds,"rank":rank,"kind":"dragon","boss_id":boss_id})

func _spawn_bramble_wraith(distance:float,angle:float,fixed_position:Variant=null,rank:int=2)->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new();root.name="Bramble Wraith";root.set_meta("always_streamed",true);add_child(root)
    var pos:Vector3=fixed_position if fixed_position is Vector3 else player.global_position+Vector3(cos(angle),0,sin(angle))*distance
    if not (fixed_position is Vector3):
        for attempt in range(10):
            if (not walkable_sampler.is_valid() or walkable_sampler.call(pos.x,pos.z)) and not _inside_safe_zone(pos):break
            var retry:=angle+float(attempt+1)*.51;pos=player.global_position+Vector3(cos(retry),0,sin(retry))*(distance+float(attempt)*11.0)
    root.global_position=_ground(pos)
    var visual:=Node3D.new();visual.name="WraithVisual";root.add_child(visual)
    var bark:=Color(.075,.095,.055);var bark_light:=Color(.15,.19,.085);var moss:=Color(.16,.30,.10);var thorn:=Color(.30,.25,.12);var glow:=Color(.42,1.0,.12)
    _dragon_part(visual,"RootPelvis",Vector3(0,.77,0),Vector3(.48,.55,.38),bark)
    _dragon_part(visual,"HollowTorso",Vector3(0,1.30,0),Vector3(.52,1.05,.42),bark)
    _dragon_part(visual,"RibMoss",Vector3(0,1.36,-.23),Vector3(.42,.62,.10),moss)
    _dragon_part(visual,"Skull",Vector3(0,2.03,-.02),Vector3(.43,.52,.38),bark_light)
    for side in [-1.0,1.0]:
        _dragon_part(visual,"Eye%s"%side,Vector3(side*.13,2.10,-.22),Vector3(.07,.08,.055),glow,true)
        _dragon_beam(visual,Vector3(side*.18,2.24,.02),Vector3(side*.46,2.62,.02),.035,thorn)
        _dragon_beam(visual,Vector3(side*.45,2.61,.02),Vector3(side*.67,2.72,.04),.025,thorn)
        _dragon_beam(visual,Vector3(side*.42,2.57,.02),Vector3(side*.53,2.82,.03),.020,thorn)
        var arm_root:=Node3D.new();arm_root.name="ArmL" if side<0 else "ArmR";visual.add_child(arm_root)
        _dragon_beam(arm_root,Vector3(side*.22,1.66,0),Vector3(side*.55,1.16,-.04),.060,bark_light)
        _dragon_beam(arm_root,Vector3(side*.55,1.16,-.04),Vector3(side*.60,.61,-.18),.045,bark)
        for claw in range(3):_dragon_cone(arm_root,Vector3(side*(.54+float(claw)*.045),.42,-.22),.025,.32,thorn,Vector3.ZERO)
        _dragon_beam(visual,Vector3(side*.15,.76,0),Vector3(side*.24,.28,.02),.075,bark)
        _dragon_part(visual,"RootFoot%s"%side,Vector3(side*.25,.10,-.10),Vector3(.24,.17,.50),bark_light)
    for tuft in range(5):
        var tx:=-.20+float(tuft)*.10
        _dragon_cone(visual,Vector3(tx,1.75,.08),.045,.34,moss,Vector3(0,0,tx*2.0))
    var flash:=StandardMaterial3D.new();flash.albedo_color=Color(.55,1,.14);flash.emission_enabled=true;flash.emission=Color(.25,1,.04);flash.emission_energy_multiplier=2.2
    var danger:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    minions.append({"node":root,"hp":78.0*danger*(1.0+float(maxi(0,rank-2))*.14),"phase":rng.randf_range(0,TAU),"attack":0.0,"windup":0.0,"knockback":Vector3.ZERO,"elite":rank>=4,"base_scale":1.0,"animation":null,"anim_lock":0.0,"flash_time":0.0,"flash_material":flash,"dead":false,"death_time":0.0,"dungeon":false,"floor_y":root.global_position.y,"bounds":Rect2(),"rank":rank,"kind":"bramble_wraith","attack_damage":9.0*danger})


func _spawn_ashfang(distance:float,angle:float,runt:bool,fixed_position:Variant=null,rank_override:int=0)->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new()
    root.name="Ashfang Runt" if runt else "Ashfang Pack Leader"
    root.set_meta("always_streamed",true)
    add_child(root)
    var pos:Vector3=fixed_position if fixed_position is Vector3 else player.global_position+Vector3(cos(angle),0,sin(angle))*distance
    if not (fixed_position is Vector3):
        for attempt in range(10):
            if (not walkable_sampler.is_valid() or walkable_sampler.call(pos.x,pos.z)) and not _inside_safe_zone(pos):break
            var retry_angle:=angle+float(attempt+1)*.43
            pos=player.global_position+Vector3(cos(retry_angle),0,sin(retry_angle))*(distance+float(attempt)*8.0)
    root.global_position=_ground(pos)
    var visual:=ASHFANG_SCENE.instantiate() as Node3D
    if visual==null:
        root.queue_free()
        push_error("The authored Ashfang Hound failed to instantiate.")
        return
    visual.name="AshfangVisual"
    # The Blender asset is authored toward -Y; match the imported imp forward
    # convention so the common look_at path produces a forward-running hound.
    visual.rotation.y=PI
    root.add_child(visual)
    var animation_player:=_find_animation_player(visual)
    if animation_player:
        for clip in ["Idle","Run"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
        for clip in ["Attack","Hit","Death"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_NONE
        animation_player.play("Idle")
    var base_scale:=.54 if runt else .82
    root.scale=Vector3.ONE*base_scale
    var flash:=StandardMaterial3D.new()
    flash.albedo_color=Color(1.0,.12,.015)
    flash.emission_enabled=true
    flash.emission=Color(1.0,.035,.002)
    flash.emission_energy_multiplier=3.2
    flash.roughness=.68
    var enemy_rank:=rank_override if rank_override>0 else (2 if runt else 3)
    var danger:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    var rank_factor:=1.0+float(maxi(0,enemy_rank-(2 if runt else 3)))*.16
    minions.append({
        "node":root,
        "hp":(56.0 if runt else 165.0)*danger*rank_factor,
        "phase":rng.randf_range(0,TAU),
        "attack":rng.randf_range(.2,.9),
        "windup":0.0,
        "knockback":Vector3.ZERO,
        "elite":not runt,
        "base_scale":base_scale,
        "animation":animation_player,
        "anim_lock":0.0,
        "flash_time":0.0,
        "flash_material":flash,
        "dead":false,
        "death_time":0.0,
        "dungeon":false,
        "floor_y":root.global_position.y,
        "bounds":Rect2(),
        "rank":enemy_rank,
        "kind":"ashfang_runt" if runt else "ashfang",
        "move_speed":4.05 if runt else 3.55,
        "aggro_range":39.0,
        "attack_range":2.15 if runt else 2.45,
        "attack_cooldown":1.15 if runt else 1.55,
        "windup_duration":.24 if runt else .34,
        "anim_lock_duration":.52 if runt else .68,
        "attack_damage":(7.0 if runt else 13.0)*danger,
    })


func _spawn_frost_troll(position:Vector3,rank:int,member:int=0)->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new()
    root.name="Frost Troll"
    root.set_meta("always_streamed",true)
    add_child(root)
    root.global_position=_ground(position)
    var visual:=FROST_TROLL_SCENE.instantiate() as Node3D
    if visual==null:
        root.queue_free()
        push_error("The authored Frost Troll failed to instantiate.")
        return
    visual.name="FrostTrollModel"
    visual.rotation.y=PI
    root.add_child(visual)
    var base_scale:=.78+float(member%2)*.045
    root.scale=Vector3.ONE*base_scale
    var flash:=StandardMaterial3D.new()
    flash.albedo_color=Color(.43,.88,1.0)
    flash.emission_enabled=true
    flash.emission=Color(.12,.52,.72)
    flash.emission_energy_multiplier=2.6
    flash.roughness=.58
    var danger:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    var rank_factor:=1.0+float(maxi(0,rank-4))*.18
    minions.append({
        "node":root,
        "hp":285.0*danger*rank_factor,
        "max_hp":285.0*danger*rank_factor,
        "phase":rng.randf_range(0,TAU),
        "attack":rng.randf_range(.35,1.1),
        "windup":0.0,
        "knockback":Vector3.ZERO,
        "elite":rank>=6,
        "base_scale":base_scale,
        "animation":null,
        "anim_lock":0.0,
        "flash_time":0.0,
        "flash_material":flash,
        "dead":false,
        "death_time":0.0,
        "dungeon":false,
        "floor_y":root.global_position.y,
        "bounds":Rect2(),
        "rank":rank,
        "kind":"frost_troll",
        "move_speed":1.72,
        "aggro_range":45.0,
        "attack_range":3.25,
        "attack_cooldown":2.15,
        "windup_duration":.72,
        "anim_lock_duration":1.08,
        "attack_damage":22.0*danger,
    })


func _animate_frost_troll(enemy:Dictionary,moving:bool)->void:
    var model:=enemy.node.get_node_or_null("FrostTrollModel") as Node3D
    if not is_instance_valid(model):return
    var left:=model.find_child("ArmPivotL",true,false) as Node3D
    var right:=model.find_child("ArmPivotR",true,false) as Node3D
    var club:=model.find_child("ClubPivot",true,false) as Node3D
    var neck:=model.find_child("NeckPivot",true,false) as Node3D
    var phase:=float(enemy.get("phase",0.0))
    var stride:=sin(phase*.72)*(.16 if moving else .035)
    var winding:=float(enemy.get("windup",0.0))>0.0
    if left:left.rotation.x=lerpf(left.rotation.x,-stride,.22)
    if right:right.rotation.x=lerpf(right.rotation.x,stride+(-.82 if winding else 0.0),.22)
    if club:club.rotation.x=lerpf(club.rotation.x,-.90 if winding else stride*.35,.24)
    if neck:neck.rotation.z=sin(phase*.31)*.025


func _spawn_rimecrawler(position:Vector3,rank:int,member:int=0)->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new();root.name="Rimecrawler";root.set_meta("always_streamed",true);add_child(root)
    root.global_position=_ground(position)
    var visual:=RIMECRAWLER_SCENE.instantiate() as Node3D
    if visual==null:
        root.queue_free();push_error("The authored Rimecrawler failed to instantiate.");return
    visual.name="RimecrawlerModel";visual.rotation.y=PI;root.add_child(visual)
    var base_scale:=.86+float(member%3)*.035
    root.scale=Vector3.ONE*base_scale
    var collision_body:=AnimatableBody3D.new();collision_body.name="RimecrawlerCollision";collision_body.collision_layer=1;collision_body.collision_mask=0;collision_body.sync_to_physics=true;root.add_child(collision_body)
    var collision_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=1.0;capsule.height=1.45;collision_shape.shape=capsule;collision_shape.position=Vector3(0,.68,0);collision_body.add_child(collision_shape)
    var flash:=StandardMaterial3D.new();flash.albedo_color=Color(.38,.88,1.0);flash.emission_enabled=true;flash.emission=Color(.08,.46,.68);flash.emission_energy_multiplier=2.8;flash.roughness=.46
    var danger:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    var rank_factor:=1.0+float(maxi(0,rank-4))*.15
    var health:=148.0*danger*rank_factor
    minions.append({
        "node":root,"hp":health,"max_hp":health,"phase":rng.randf_range(0,TAU),"attack":rng.randf_range(.2,.9),
        "windup":0.0,"knockback":Vector3.ZERO,"elite":rank>=6,"base_scale":base_scale,"animation":null,"anim_lock":0.0,
        "flash_time":0.0,"flash_material":flash,"dead":false,"death_time":0.0,"dungeon":false,"floor_y":root.global_position.y,
        "bounds":Rect2(),"rank":rank,"kind":"rimecrawler","move_speed":3.18,"aggro_range":37.0,"attack_range":2.35,
        "attack_cooldown":1.42,"windup_duration":.34,"anim_lock_duration":.60,"attack_damage":14.0*danger,
    })


func _animate_rimecrawler(enemy:Dictionary,moving:bool)->void:
    var model:=enemy.node.get_node_or_null("RimecrawlerModel") as Node3D
    if not is_instance_valid(model):return
    var phase:=float(enemy.get("phase",0.0))
    var winding:=float(enemy.get("windup",0.0))>0.0
    for side_name in ["L","R"]:
        var side_phase:=0.0 if side_name=="L" else PI
        for leg_index in range(3):
            var pivot:=model.find_child("LegPivot_%s%d"%[side_name,leg_index],true,false) as Node3D
            if not pivot:continue
            var gait:=sin(phase+side_phase+float(leg_index)*1.72)*(.30 if moving else .045)
            pivot.rotation.x=lerpf(pivot.rotation.x,gait+(-.18 if winding and leg_index==0 else 0.0),.28)
            pivot.rotation.z=lerpf(pivot.rotation.z,sin(phase*.52+float(leg_index))*.035,.18)
    var thorax:=model.find_child("Thorax",true,false) as Node3D
    if thorax:thorax.rotation.z=sin(phase*.44)*.028
    for side_name in ["L","R"]:
        var mandible:=model.find_child("Mandible_%s"%side_name,true,false) as Node3D
        if mandible:mandible.rotation.y=lerpf(mandible.rotation.y,(.28 if winding else .04)*(1.0 if side_name=="L" else -1.0),.24)


func _spawn_ashscale_basilisk(position:Vector3,rank:int,member:int=0)->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new();root.name="Ashscale Basilisk";root.set_meta("always_streamed",true);add_child(root)
    root.global_position=_ground(position)
    var visual:=ASHSCALE_BASILISK_SCENE.instantiate() as Node3D
    if visual==null:
        root.queue_free();push_error("The authored Ashscale Basilisk failed to instantiate.");return
    visual.name="AshscaleBasiliskModel";visual.rotation.y=PI;root.add_child(visual)
    var base_scale:=.78+float(member%3)*.035
    root.scale=Vector3.ONE*base_scale
    var collision_body:=AnimatableBody3D.new();collision_body.name="AshscaleCollision";collision_body.collision_layer=1;collision_body.collision_mask=0;collision_body.sync_to_physics=true;root.add_child(collision_body)
    var collision_shape:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.88;capsule.height=1.60;collision_shape.shape=capsule;collision_shape.position=Vector3(0,.72,0);collision_body.add_child(collision_shape)
    var flash:=StandardMaterial3D.new();flash.albedo_color=Color(1.0,.43,.08);flash.emission_enabled=true;flash.emission=Color(.82,.08,.01);flash.emission_energy_multiplier=2.9;flash.roughness=.52
    var danger:=maxf(1.0,float(profile.get("difficulty_multiplier",1.0)))
    var rank_factor:=1.0+float(maxi(0,rank-4))*.16
    var health:=172.0*danger*rank_factor
    minions.append({
        "node":root,"hp":health,"max_hp":health,"phase":rng.randf_range(0,TAU),"attack":rng.randf_range(.25,.95),
        "windup":0.0,"knockback":Vector3.ZERO,"elite":rank>=6,"base_scale":base_scale,"animation":null,"anim_lock":0.0,
        "flash_time":0.0,"flash_material":flash,"dead":false,"death_time":0.0,"dungeon":false,"floor_y":root.global_position.y,
        "bounds":Rect2(),"rank":rank,"kind":"ashscale_basilisk","move_speed":2.82,"aggro_range":39.0,"attack_range":2.65,
        "attack_cooldown":1.58,"windup_duration":.42,"anim_lock_duration":.72,"attack_damage":16.0*danger,
    })


func _animate_ashscale_basilisk(enemy:Dictionary,moving:bool)->void:
    var model:=enemy.node.get_node_or_null("AshscaleBasiliskModel") as Node3D
    if not is_instance_valid(model):return
    var phase:=float(enemy.get("phase",0.0))
    var winding:=float(enemy.get("windup",0.0))>0.0
    for side_name in ["L","R"]:
        var side_phase:=0.0 if side_name=="L" else PI
        for leg_name in ["F","R"]:
            var leg_phase:=0.0 if leg_name=="F" else PI
            var pivot:=model.find_child("LegPivot_%s%s"%[side_name,leg_name],true,false) as Node3D
            if not pivot:continue
            var gait:=sin(phase+side_phase+leg_phase)*(.24 if moving else .035)
            pivot.rotation.x=lerpf(pivot.rotation.x,gait,.26)
            pivot.rotation.z=lerpf(pivot.rotation.z,sin(phase*.47+side_phase)*.025,.18)
    var jaw:=model.find_child("JawPivot",true,false) as Node3D
    if jaw:jaw.rotation.x=lerpf(jaw.rotation.x,.40 if winding else .035+sin(phase*.31)*.018,.25)
    var tail_0:=model.find_child("TailPivot_0",true,false) as Node3D
    var tail_1:=model.find_child("TailPivot_1",true,false) as Node3D
    if tail_0:tail_0.rotation.y=sin(phase*.52)*(.18 if moving else .07)
    if tail_1:tail_1.rotation.y=sin(phase*.52+.78)*(.25 if moving else .10)
    var throat:=model.find_child("EmberThroat",true,false) as Node3D
    if throat:
        var pulse:=1.0+sin(phase*.38)*.055+(.10 if winding else 0.0)
        throat.scale=Vector3.ONE*pulse


func _spawn_zombie(world_point:Vector2,variant:String,encounter_id:String,dungeon:=false,fixed_position:Vector3=Vector3(INF,INF,INF),dungeon_bounds:Rect2=Rect2())->void:
    if not is_instance_valid(player):return
    var root:=Node3D.new();root.name="Gravebound %s"%variant.capitalize();root.set_meta("always_streamed",true);add_child(root)
    var position:=fixed_position if fixed_position.is_finite() else _ground(Vector3(world_point.x,0,world_point.y))
    root.global_position=position
    var visual:=GRAVEBOUND_SCENE.instantiate() as Node3D
    if visual==null:
        root.queue_free();push_error("The authored Gravebound zombie failed to instantiate.");return
    visual.name="GraveboundVisual";visual.rotation.y=PI;root.add_child(visual)
    var collision_body:=AnimatableBody3D.new();collision_body.name="GraveboundCollision";collision_body.collision_layer=1;collision_body.collision_mask=0;collision_body.sync_to_physics=true;root.add_child(collision_body)
    var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.34 if variant=="runner" else (.48 if variant=="champion" else .40);capsule.height=1.62;collision.shape=capsule;collision.position=Vector3(0,.84,0);collision_body.add_child(collision)
    var animation_player:=_find_animation_player(visual)
    if animation_player:
        for clip in ["Idle","Walk","Run"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
        for clip in ["Attack","Hit","Stagger","Knockdown","Death"]:
            if animation_player.has_animation(clip):animation_player.get_animation(clip).loop_mode=Animation.LOOP_NONE
        animation_player.play("Idle")
    var stats:Dictionary={"hp":64.0,"scale":.96,"speed":1.75,"aggro":31.0,"range":2.05,"cooldown":1.52,"windup":.42,"damage":9.0,"rank":1,"elite":false,"movement":"Walk"}
    match variant:
        "runner":stats.merge({"hp":48.0,"scale":.92,"speed":4.35,"aggro":42.0,"range":1.85,"cooldown":1.05,"windup":.22,"damage":7.0,"rank":1,"movement":"Run"},true)
        "graveguard":stats.merge({"hp":175.0,"scale":1.04,"speed":2.05,"aggro":36.0,"range":2.25,"cooldown":1.72,"windup":.48,"damage":14.0,"rank":3,"elite":true,"movement":"Walk"},true)
        "carrier":stats.merge({"hp":118.0,"scale":1.08,"speed":1.48,"aggro":34.0,"range":2.35,"cooldown":1.85,"windup":.52,"damage":10.0,"rank":2,"movement":"Walk"},true)
        "champion":stats.merge({"hp":980.0,"scale":1.34,"speed":2.22,"aggro":70.0,"range":2.75,"cooldown":1.45,"windup":.46,"damage":22.0,"rank":6,"elite":true,"movement":"Walk"},true)
    root.scale=Vector3.ONE*float(stats.scale)
    _add_zombie_variant_visual(root,variant)
    var health_fill:=_add_zombie_health_bar(root,variant)
    var audio_player:=AudioStreamPlayer3D.new();audio_player.name="GraveboundVoice";audio_player.max_distance=38.0;audio_player.unit_size=7.0;audio_player.volume_db=-7.0;root.add_child(audio_player)
    var flash:=StandardMaterial3D.new();flash.albedo_color=Color(.62,1.0,.22);flash.emission_enabled=true;flash.emission=Color(.28,1.0,.06);flash.emission_energy_multiplier=2.1
    minions.append({
        "node":root,"hp":stats.hp,"max_hp":stats.hp,"phase":rng.randf_range(0,TAU),"attack":rng.randf_range(.15,.75),"windup":0.0,"knockback":Vector3.ZERO,
        "elite":stats.elite,"base_scale":stats.scale,"animation":animation_player,"anim_lock":0.0,"flash_time":0.0,"flash_material":flash,"dead":false,"death_time":0.0,
        "dungeon":dungeon,"floor_y":position.y,"bounds":dungeon_bounds,"rank":stats.rank,"kind":"zombie_%s"%variant,"zombie_variant":variant,"encounter_id":encounter_id,
        "move_speed":stats.speed,"aggro_range":stats.aggro,"attack_range":stats.range,"attack_cooldown":stats.cooldown,"windup_duration":stats.windup,"anim_lock_duration":.74,"attack_damage":stats.damage,
        "movement_animation":stats.movement,"audio":audio_player,"health_fill":health_fill,"groan_time":rng.randf_range(4.0,11.0),"plague_tick":rng.randf_range(1.0,2.0),"boss_phase":1,"summon_2":false,"summon_3":false,
    })


func _add_zombie_variant_visual(root:Node3D,variant:String)->void:
    var gear:=Node3D.new();gear.name="VariantEquipment";root.add_child(gear)
    var iron:=Color(.14,.16,.15);var rust:=Color(.28,.13,.055);var cloth:=Color(.16,.12,.075);var plague:=Color(.34,.52,.10)
    if variant in ["graveguard","champion"]:
        # Armor overlaps the body and is deliberately compact enough to retain
        # the silhouette and animation readability of the authored corpse.
        _service_box(gear,Vector3(0,1.46,.015),Vector3(.66,.56,.38),iron)
        _service_box(gear,Vector3(0,1.77,.015),Vector3(.48,.10,.32),rust)
        var helm:=MeshInstance3D.new();var helm_mesh:=CylinderMesh.new();helm_mesh.top_radius=.23;helm_mesh.bottom_radius=.29;helm_mesh.height=.34;helm_mesh.radial_segments=12;helm.mesh=helm_mesh;helm.position=Vector3(0,2.08,0);helm.material_override=_service_material(iron);gear.add_child(helm)
        for side in [-1.0,1.0]:_service_box(gear,Vector3(side*.39,1.62,.015),Vector3(.26,.18,.42),iron).rotation.z=side*.18
    if variant=="graveguard":
        var shield:=MeshInstance3D.new();var shield_mesh:=CylinderMesh.new();shield_mesh.top_radius=.48;shield_mesh.bottom_radius=.48;shield_mesh.height=.12;shield_mesh.radial_segments=12;shield.mesh=shield_mesh;shield.position=Vector3(-.68,1.12,.12);shield.rotation.z=PI*.5;shield.material_override=_service_material(Color(.20,.24,.21));gear.add_child(shield)
        _service_box(gear,Vector3(-.75,1.12,-.04),Vector3(.12,.78,.12),rust)
    elif variant=="carrier":
        for i in range(3):
            var sack:=MeshInstance3D.new();var sack_mesh:=SphereMesh.new();sack_mesh.radius=.34;sack_mesh.height=.72;sack_mesh.radial_segments=12;sack_mesh.rings=7;sack.mesh=sack_mesh;sack.position=Vector3((float(i)-1.0)*.24,1.38,.31+float(i%2)*.10);sack.material_override=_service_material(plague.darkened(float(i)*.045));gear.add_child(sack)
        var fumes:=GPUParticles3D.new();fumes.name="PlagueMotes";fumes.amount=10;fumes.lifetime=2.2;fumes.position=Vector3(0,1.55,.30);var process:=ParticleProcessMaterial.new();process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE;process.emission_sphere_radius=.34;process.initial_velocity_min=.18;process.initial_velocity_max=.5;process.gravity=Vector3(0,.24,0);process.scale_min=.06;process.scale_max=.16;process.color=Color(.34,.70,.10,.50);fumes.process_material=process;var mote:=SphereMesh.new();mote.radius=.05;mote.height=.10;mote.radial_segments=6;mote.rings=3;fumes.draw_pass_1=mote;gear.add_child(fumes)
    elif variant=="champion":
        _service_box(gear,Vector3(0,1.08,.015),Vector3(.58,.24,.42),rust)
        for x in [-.22,0.0,.22]:
            var spike:=MeshInstance3D.new();var spike_mesh:=CylinderMesh.new();spike_mesh.top_radius=0.0;spike_mesh.bottom_radius=.065;spike_mesh.height=.42;spike_mesh.radial_segments=8;spike.mesh=spike_mesh;spike.position=Vector3(x,2.42,0);spike.material_override=_service_material(rust);gear.add_child(spike)
        var aura:=OmniLight3D.new();aura.light_color=Color(.30,1.0,.08);aura.light_energy=1.15;aura.omni_range=4.8;aura.shadow_enabled=false;aura.position=Vector3(0,1.3,0);gear.add_child(aura)
    elif variant=="runner":
        _service_box(gear,Vector3(0,1.26,.22),Vector3(.46,.18,.06),cloth)


func _play_zombie_sound(m:Dictionary,stream:AudioStream)->void:
    var audio_player:=m.get("audio") as AudioStreamPlayer3D
    if not is_instance_valid(audio_player) or audio_player.playing:return
    audio_player.stream=stream;audio_player.pitch_scale=rng.randf_range(.88,1.12);audio_player.play()


func _add_zombie_health_bar(root:Node3D,variant:String)->MeshInstance3D:
    var bar_root:=Node3D.new();bar_root.name="EnemyHealthBar";bar_root.position=Vector3(0,2.63 if variant!="champion" else 2.78,0);root.add_child(bar_root)
    var width:=1.70 if variant=="champion" else 1.16
    var back:=_service_box(bar_root,Vector3(0,0,.01),Vector3(width+.10,.15,.055),Color(.025,.018,.016));back.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var fill:=_service_box(bar_root,Vector3(0,0,.055),Vector3(width,.09,.06),Color(.64,.08,.045));fill.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    if variant=="champion":
        var label:=Label3D.new();label.text="GRAVEBOUND CHAMPION";label.position=Vector3(0,.28,0);label.font_size=24;label.pixel_size=.008;label.modulate=Color(1.0,.62,.25);label.outline_size=6;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;bar_root.add_child(label)
    return fill


func _dragon_part(root:Node3D,name_value:String,pos:Vector3,size:Vector3,color:Color,emissive:bool=false)->void:
    var mesh:=MeshInstance3D.new();mesh.name=name_value;var shape:=SphereMesh.new();shape.radius=1.0;shape.height=2.0;shape.radial_segments=18;shape.rings=10;mesh.mesh=shape;mesh.position=pos;mesh.scale=size*.5
    var material:=_service_material(color)
    if emissive:
        material=material.duplicate();material.emission_enabled=true;material.emission=color;material.emission_energy_multiplier=4.0
    mesh.material_override=material;root.add_child(mesh)

func _dragon_cone(root:Node3D,pos:Vector3,radius:float,height:float,color:Color,rotation_value:Vector3)->void:
    var mesh:=MeshInstance3D.new();var shape:=CylinderMesh.new();shape.top_radius=0.0;shape.bottom_radius=radius;shape.height=height;shape.radial_segments=10;mesh.mesh=shape;mesh.position=pos;mesh.rotation=rotation_value;mesh.material_override=_service_material(color);root.add_child(mesh)

func _dragon_wing(root:Node3D,side:float,membrane_color:Color,spar_color:Color)->void:
    var wing_root:=Node3D.new();wing_root.name="WingL" if side<0.0 else "WingR";root.add_child(wing_root)
    var origin:=Vector3(side*2.15,5.15,-.25);wing_root.position=origin
    var shoulder:=Vector3.ZERO
    var knuckle:=Vector3(side*5.5,7.25,-1.05)-origin
    var tip:=Vector3(side*8.2,6.35,-2.3)-origin
    var rear:=Vector3(side*5.8,3.15,-5.15)-origin
    var inner:=Vector3(side*2.0,3.55,-3.55)-origin
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for triangle in [[shoulder,knuckle,inner],[knuckle,rear,inner],[knuckle,tip,rear]]:
        for vertex in triangle:st.set_uv(Vector2(vertex.x*.08,vertex.z*.08));st.add_vertex(vertex)
    st.generate_normals()
    var membrane:=MeshInstance3D.new();membrane.name="WingMembrane";membrane.mesh=st.commit()
    var material:=_service_material(membrane_color).duplicate() as StandardMaterial3D;material.cull_mode=BaseMaterial3D.CULL_DISABLED;material.roughness=.92;membrane.material_override=material;wing_root.add_child(membrane)
    for segment in [[shoulder,knuckle],[knuckle,tip],[knuckle,rear],[shoulder,inner],[inner,rear]]:_dragon_beam(wing_root,segment[0],segment[1],.13,spar_color)

func _dragon_beam(root:Node3D,a:Vector3,b:Vector3,radius:float,color:Color)->void:
    var direction:=b-a;var mesh:=MeshInstance3D.new();var shape:=CylinderMesh.new();shape.top_radius=radius*.82;shape.bottom_radius=radius;shape.height=direction.length();shape.radial_segments=10;mesh.mesh=shape;mesh.position=(a+b)*.5;mesh.quaternion=Quaternion(Vector3.UP,direction.normalized());mesh.material_override=_service_material(color);root.add_child(mesh)

func _tick_dragon(m:Dictionary,delta:float,player_in_safe_zone:bool)->void:
    m.phase=float(m.get("phase",0.0))+delta;m.attack=maxf(0.0,float(m.get("attack",0.0))-delta)
    var root:Node3D=m.node;var delta_pos:Vector3=player.global_position-root.global_position;var dist:=delta_pos.length()
    root.visible=dist<150.0
    if not root.visible:return
    root.look_at(Vector3(player.global_position.x,root.global_position.y,player.global_position.z),Vector3.UP)
    var walking:=dist>6.5 and dist<70.0 and not player_in_safe_zone
    if float(m.get("anim_lock",0.0))<=0.0:
        _play_minion_animation(m,"Walk" if walking else "Idle")
    if player_in_safe_zone:return
    if dist>8.0 and dist<=16.0 and float(m.attack)<=0.0:
        m.attack=4.0
        m.anim_lock=2.45
        _play_minion_animation(m,"FireBreath",true)
        var armor_value:int=player.get_equipment_state().get("armor",0)
        _damage_player(maxf(14.0,42.0-float(armor_value)*.16))
        _burst(player.global_position,Color(1.0,.16,.015),3.5)
    elif dist>6.5 and dist<70.0:
        var direction:=Vector3(delta_pos.x,0,delta_pos.z).normalized();var next:=root.global_position+direction*1.85*delta
        if _dungeon_step_allowed(m,root.global_position,next):root.global_position=Vector3(next.x,float(m.floor_y),next.z)
    elif dist<=6.5 and float(m.attack)<=0.0:
        m.attack=2.4
        m.anim_lock=1.35
        _play_minion_animation(m,"Attack",true)
        var armor_value:int=player.get_equipment_state().get("armor",0)
        _damage_player(maxf(22.0,58.0-float(armor_value)*.22))
        _impact_flash(player.global_position+Vector3.UP,Color(1.0,.12,.015),.65)

func _tick_minions(delta: float) -> void:
    var player_in_safe_zone:=_inside_safe_zone(player.global_position)
    for i in range(minions.size()-1,-1,-1):
        var m:=minions[i]
        if not is_instance_valid(m.node): minions.remove_at(i); continue
        if m.get("dead", false):
            _tick_enemy_death(m,delta)
            m.death_time = float(m.get("death_time", 0.0)) - delta
            if m.death_time <= 0.0:
                m.node.queue_free()
                minions.remove_at(i)
            continue
        if str(m.get("kind","")).begins_with("wildlife_"):
            _tick_wildlife(m,delta)
            continue
        # Dormant enemies do not need animation, overlay traversal, pathing or
        # terrain sampling. Previously every imp in every sealed dungeon paid
        # those costs 30 times per second even when kilometres away.
        var rough_delta:Vector3=player.global_position-m.node.global_position
        if m.get("kind","")!="dragon" and rough_delta.length_squared()>9216.0 and Vector3(m.get("knockback",Vector3.ZERO)).length_squared()<=0.001:
            m.node.visible=false
            continue
        m.anim_lock = maxf(0.0, float(m.get("anim_lock", 0.0)) - delta)
        m.flash_time = maxf(0.0, float(m.get("flash_time", 0.0)) - delta)
        if m.flash_time <= 0.0 and m.get("flash_applied",false):
            _set_imp_overlay(m.node, null)
            m.flash_applied=false
        if m.get("kind","")=="dragon":
            _tick_dragon(m,delta,player_in_safe_zone)
            continue
        if m.get("kind","")=="bramble_wraith":
            var wraith_visual:Node3D=m.node.get_node_or_null("WraithVisual") as Node3D
            if wraith_visual:
                wraith_visual.position.y=sin(float(m.phase)*.62)*.035
                var arm_l:Node3D=wraith_visual.get_node_or_null("ArmL") as Node3D;var arm_r:Node3D=wraith_visual.get_node_or_null("ArmR") as Node3D
                if arm_l:arm_l.rotation.x=sin(float(m.phase)*.85)*.13
                if arm_r:arm_r.rotation.x=-sin(float(m.phase)*.85)*.13
                var skull:=wraith_visual.get_node_or_null("Skull") as Node3D
                var torso:=wraith_visual.get_node_or_null("HollowTorso") as Node3D
                if skull:skull.rotation.z=sin(float(m.phase)*.55)*.055
                if torso:torso.rotation.z=-sin(float(m.phase)*.55)*.025
        var kind:String=str(m.get("kind",""))
        if kind.begins_with("zombie_"):
            m.groan_time=float(m.get("groan_time",8.0))-delta
            if float(m.groan_time)<=0.0:
                m.groan_time=rng.randf_range(7.0,15.0)
                if rough_delta.length_squared()<900.0:_play_zombie_sound(m,ZOMBIE_GROAN)
        var in_dungeon: bool = m.get("dungeon", false)
        if not in_dungeon and _inside_safe_zone(m.node.global_position):
            var outward:=Vector2(m.node.global_position.x,m.node.global_position.z)-safe_zone_center
            if outward.length_squared()<0.001:outward=Vector2.RIGHT
            outward=outward.normalized()*(safe_zone_radius+3.0)
            m.node.global_position=_ground(Vector3(safe_zone_center.x+outward.x,0.0,safe_zone_center.y+outward.y))
        var phase_speed:=7.8 if kind=="rimecrawler" else (6.3 if kind=="ashscale_basilisk" else (7.0 if kind.begins_with("ashfang") else (3.2 if kind=="frost_troll" else 5.0)))
        m.phase += delta*phase_speed; m.attack=maxf(0.0,m.attack-delta)
        var knockback:Vector3=m.get("knockback",Vector3.ZERO)
        if knockback.length_squared()>0.001:
            var pushed:Vector3=m.node.global_position+knockback*delta
            if in_dungeon:
                if _dungeon_step_allowed(m,m.node.global_position,pushed): m.node.global_position = Vector3(pushed.x, float(m.floor_y), pushed.z)
            elif not _inside_safe_zone(pushed) and (not walkable_sampler.is_valid() or walkable_sampler.call(pushed.x,pushed.z)):m.node.global_position=_ground(pushed)
            m.knockback=knockback.move_toward(Vector3.ZERO,18.0*delta)
        var delta_pos:Vector3=player.global_position-m.node.global_position; var dist:=delta_pos.length()
        if dist > 96.0 and knockback.length_squared() <= 0.001:
            m.node.visible = false
            continue
        m.node.visible = true
        if kind=="zombie_carrier" and not player_in_safe_zone:
            m.plague_tick=maxf(0.0,float(m.get("plague_tick",1.2))-delta)
            if dist<4.6 and float(m.plague_tick)<=0.0:
                m.plague_tick=2.25
                _damage_player(3.0)
                _burst(m.node.global_position,Color(.34,.68,.08),2.8)
        if kind=="zombie_champion":
            var health_fraction:=float(m.hp)/maxf(1.0,float(m.get("max_hp",m.hp)))
            var boss_phase:=3 if health_fraction<.34 else (2 if health_fraction<.67 else 1)
            if boss_phase!=int(m.get("boss_phase",1)):
                m.boss_phase=boss_phase
                _burst(m.node.global_position,Color(.30,1.0,.08),4.5+float(boss_phase))
                _notify("Gravebound Champion — Phase %d"%boss_phase,Color(1.0,.34,.12))
            if boss_phase>=2 and not bool(m.get("summon_2",false)):
                m.summon_2=true
                for offset in [Vector3(-5,0,2),Vector3(5,0,2)]:_spawn_zombie(Vector2.ZERO,"runner","champion_reinforcements",true,m.node.global_position+offset,m.get("bounds",Rect2()))
            if boss_phase>=3 and not bool(m.get("summon_3",false)):
                m.summon_3=true
                _spawn_zombie(Vector2.ZERO,"carrier","champion_reinforcements",true,m.node.global_position+Vector3(0,0,6),m.get("bounds",Rect2()))
                m.move_speed=2.72;m.attack_damage=27.0
            m.slam_cooldown=maxf(0.0,float(m.get("slam_cooldown",2.8))-delta)
            if dist<6.5 and float(m.slam_cooldown)<=0.0 and not player_in_safe_zone:
                m.slam_cooldown=4.2 if boss_phase<3 else 3.1
                m.attack=maxf(float(m.attack),1.2);m.anim_lock=1.0
                _play_minion_animation(m,"Attack",true);_play_zombie_sound(m,ZOMBIE_ATTACK)
                _burst(m.node.global_position,Color(.42,.72,.12),6.5)
                var armor_value:int=player.get_equipment_state().get("armor",0)
                _damage_player(maxf(8.0,28.0-float(armor_value)*.11))
        var windup:float=float(m.get("windup",0.0))
        if windup>0.0 and player_in_safe_zone:
            m.windup=0.0
        elif windup>0.0:
            var previous:=windup;windup=maxf(0.0,windup-delta);m.windup=windup
            var base_scale:float=float(m.get("base_scale",.62))
            m.node.scale=Vector3(1.0+windup*.28,1.0-windup*.18,1.0+windup*.28)*base_scale
            if previous>0.0 and windup<=0.0 and dist<=2.25:
                var armor_value:int=player.get_equipment_state().get("armor",0)
                var default_damage:=5.0+float(int(m.get("rank",1))-1)*2.5
                var incoming:=maxf(1.0,float(m.get("attack_damage",default_damage))-float(armor_value)*.065)
                _damage_player(incoming);_impact_flash(player.global_position+Vector3.UP*.8,Color(1,.18,.06),.22)
        var aggro_range:float=float(m.get("aggro_range",32.0))
        var attack_range:float=float(m.get("attack_range",1.85))
        var move_speed:float=float(m.get("move_speed",2.25))
        if kind=="frost_troll":_animate_frost_troll(m,windup<=0.0 and not player_in_safe_zone and dist<aggro_range and dist>attack_range)
        elif kind=="rimecrawler":_animate_rimecrawler(m,windup<=0.0 and not player_in_safe_zone and dist<aggro_range and dist>attack_range)
        elif kind=="ashscale_basilisk":_animate_ashscale_basilisk(m,windup<=0.0 and not player_in_safe_zone and dist<aggro_range and dist>attack_range)
        if windup<=0.0 and not player_in_safe_zone and dist < aggro_range and dist > attack_range:
            var dir: Vector3 = Vector3(delta_pos.x,0,delta_pos.z).normalized(); var next: Vector3 = m.node.global_position+dir*move_speed*delta
            if in_dungeon:
                if _dungeon_step_allowed(m,m.node.global_position,next):
                    m.node.global_position=Vector3(next.x,float(m.floor_y),next.z)
                else:
                    # Slide along the obstruction instead of tunnelling through
                    # it or standing motionless against a dungeon wall.
                    for side in [-1.0,1.0]:
                        var side_dir:Vector3=dir.rotated(Vector3.UP,float(side)*PI*.5)
                        var alternate:Vector3=m.node.global_position+side_dir*move_speed*.91*delta
                        if _dungeon_step_allowed(m,m.node.global_position,alternate):m.node.global_position=Vector3(alternate.x,float(m.floor_y),alternate.z);break
            elif not _inside_safe_zone(next) and (not walkable_sampler.is_valid() or walkable_sampler.call(next.x,next.z)): m.node.global_position=_ground(next)
            m.node.look_at(Vector3(player.global_position.x,m.node.global_position.y,player.global_position.z),Vector3.UP)
            _play_minion_animation(m,str(m.get("movement_animation","Run")))
        elif windup<=0.0 and not player_in_safe_zone and dist <= attack_range and m.attack <= 0:
            var base_scale:float=float(m.get("base_scale",.62))
            m.attack=float(m.get("attack_cooldown",1.25))
            m.windup=float(m.get("windup_duration",.38))
            m.node.scale=Vector3(1.10,.90,1.10)*base_scale
            m.anim_lock=float(m.get("anim_lock_duration",.62))
            _play_minion_animation(m,"Attack",true)
            if kind.begins_with("zombie_"):_play_zombie_sound(m,ZOMBIE_ATTACK)
        elif float(m.get("anim_lock",0.0)) <= 0.0:
            _play_minion_animation(m, "Idle")
        if float(m.get("windup",0.0))<=0.0:m.node.scale=m.node.scale.lerp(Vector3.ONE*float(m.get("base_scale",.62)),delta*7.0)
        var locomotion_bob:=0.0 if kind.begins_with("ashfang") or kind in ["rimecrawler","ashscale_basilisk"] else sin(m.phase)*.018
        m.node.position.y=(float(m.floor_y) if in_dungeon else _ground(m.node.global_position).y)+locomotion_bob


func _tick_wildlife(animal:Dictionary,delta:float)->void:
    var root:Node3D=animal.node
    var offset:Vector3=root.global_position-player.global_position
    var distance_squared:=offset.length_squared()
    if distance_squared>22500.0:
        root.visible=false
        return
    root.visible=true
    var distance:=sqrt(distance_squared)
    var species:=str(animal.get("species","deer"))
    animal.phase=float(animal.get("phase",0.0))+delta
    animal.wander_time=float(animal.get("wander_time",0.0))-delta
    var direction2:Vector2=animal.get("wander_direction",Vector2.UP)
    var moving:=false
    var speed:=0.0
    if distance<22.0:
        direction2=Vector2(offset.x,offset.z).normalized()
        if direction2.length_squared()<.01:direction2=Vector2.RIGHT
        speed=float(animal.get("flee_speed",6.0))
        moving=true
        animal.wander_time=rng.randf_range(2.0,4.0)
    else:
        var home:Vector2=animal.get("home",Vector2.ZERO)
        var planar_position:=Vector2(root.global_position.x,root.global_position.z)
        var home_offset:=home-planar_position
        if home_offset.length()>float(animal.get("home_radius",220.0))*.88:
            direction2=home_offset.normalized()
            speed=1.55 if species=="deer" else 1.15
            moving=true
        elif float(animal.wander_time)<=0.0:
            var heading:=rng.randf_range(-PI,PI)
            direction2=Vector2(cos(heading),sin(heading))
            animal.wander_time=rng.randf_range(2.2,6.5)
            animal.moving=rng.randf()<.68
        else:
            moving=bool(animal.get("moving",false))
            speed=(1.30 if species=="deer" else .92) if moving else 0.0
    animal.wander_direction=direction2
    animal.moving=moving
    if moving and direction2.length_squared()>.01:
        var move_direction:=Vector3(direction2.x,0.0,direction2.y).normalized()
        var next:=root.global_position+move_direction*speed*delta
        var allowed:bool=not walkable_sampler.is_valid() or bool(walkable_sampler.call(next.x,next.z))
        if allowed:
            var next_ground:=_ground(next)
            if absf(next_ground.y-root.global_position.y)<1.15:
                root.global_position=next_ground
                root.look_at(root.global_position+move_direction,Vector3.UP)
            else:
                animal.wander_direction=direction2.rotated(1.91)
                animal.wander_time=.35
        else:
            animal.wander_direction=direction2.rotated(1.57)
            animal.wander_time=.35
    else:
        root.global_position=_ground(root.global_position)
    _animate_wildlife(animal,moving,speed)


func _animate_wildlife(animal:Dictionary,moving:bool,speed:float)->void:
    var visual:Node3D=animal.node.get_node_or_null("WildlifeVisual") as Node3D
    if visual==null:return
    var species:=str(animal.get("species","deer"))
    var phase:=float(animal.get("phase",0.0))*(8.5 if moving else 2.0)*(1.0+speed*.06)
    var swing:=sin(phase)*(.48 if moving else .035)
    var names:Array[String]=["FrontLegL","FrontLegR","RearLegL","RearLegR"] if species!="grouse" else ["LegL","LegR"]
    for index in range(names.size()):
        var pivot:=visual.find_child(names[index],true,false) as Node3D
        if pivot:pivot.rotation.x=swing*(-1.0 if index%2==0 else 1.0)
    for ear_name in ["EarL","EarR"]:
        var ear:=visual.find_child(ear_name,true,false) as Node3D
        if ear:ear.rotation.z=sin(phase*.27+float(ear_name.length()))*.055
    var tail:=visual.find_child("TailPivot",true,false) as Node3D
    if tail:tail.rotation.z=sin(phase*.42)*(.16 if moving else .045)
    visual.position.y=(absf(sin(phase))*.035 if moving else sin(phase*.22)*.012)


func _inside_dungeon_bounds(minion: Dictionary, position: Vector3) -> bool:
    var bounds: Rect2 = minion.get("bounds", Rect2())
    return bounds.has_point(Vector2(position.x, position.z))


func _dungeon_step_allowed(minion:Dictionary,from_position:Vector3,to_position:Vector3)->bool:
    if not _inside_dungeon_bounds(minion,to_position):return false
    var planar:=Vector3(to_position.x-from_position.x,0,to_position.z-from_position.z)
    if planar.length_squared()<.000001:return true
    var perpendicular:=Vector3(-planar.z,0,planar.x).normalized()*.32
    var exclusions:Array[RID]=[]
    if is_instance_valid(player):exclusions.append(player.get_rid())
    var space:=get_world_3d().direct_space_state
    for offset in [Vector3.ZERO,perpendicular,-perpendicular]:
        var query:=PhysicsRayQueryParameters3D.create(from_position+Vector3.UP*.72+offset,to_position+Vector3.UP*.72+offset,1,exclusions)
        if not space.intersect_ray(query).is_empty():return false
    return true

func _inside_safe_zone(position:Vector3)->bool:
    return Vector2(position.x,position.z).distance_squared_to(safe_zone_center)<safe_zone_radius*safe_zone_radius

func _damage(m: Dictionary, amount: float, hit_direction:Vector3=Vector3.ZERO) -> void:
    if m.get("dead", false): return
    var kind:String=str(m.get("kind",""))
    if kind=="zombie_graveguard":amount*=.68
    if _admin_one_hit_kill:
        amount=maxf(amount,float(m.get("hp",1.0)))
    var base_scale:float=float(m.get("base_scale",.62));m.hp -= amount;m.node.scale=Vector3(1.28,.75,1.28)*base_scale
    var health_fill:=m.get("health_fill") as MeshInstance3D
    if is_instance_valid(health_fill):health_fill.scale.x=clampf(float(m.hp)/maxf(1.0,float(m.get("max_hp",m.hp+amount))),0.0,1.0)
    if hit_direction.length_squared()>0.001:m.knockback=Vector3(hit_direction.x,0.0,hit_direction.z).normalized()*(5.5 if not m.get("elite",false) else 2.8)
    m.flash_time=.12
    m.flash_applied=true
    _set_imp_overlay(m.node,m.get("flash_material"))
    if m.hp <= 0:
        var death_pos: Vector3 = m.node.global_position
        var was_elite: bool = m.get("elite", false)
        var is_dragon:bool=m.get("kind","")=="dragon"
        kind=m.get("kind","")
        m.dead=true
        m.death_elapsed=0.0
        m.death_time=3.5 if is_dragon else (2.45 if kind=="frost_troll" else (2.25 if kind=="ashscale_basilisk" else (2.20 if kind=="rimecrawler" else (2.1 if kind=="bramble_wraith" else (2.0 if kind.begins_with("ashfang") else 1.45)))))
        m.node.scale=Vector3.ONE*base_scale
        if is_instance_valid(health_fill) and is_instance_valid(health_fill.get_parent()):health_fill.get_parent().visible=false
        _play_minion_animation(m,"Death",true)
        if kind.begins_with("wildlife_"):
            var wildlife_collision:=m.get("collision") as CollisionObject3D
            if is_instance_valid(wildlife_collision):wildlife_collision.collision_layer=0
            var species:=str(m.get("species","deer"))
            var meat_amount:=3 if species=="deer" else 1
            _spawn_world_drop(death_pos,{"kind":"material","material":"raw_meat","amount":meat_amount,"name":"Raw Game Meat"},false)
            if species in ["deer","hare"]:
                _spawn_world_drop(death_pos+Vector3(.48,0,.20),{"kind":"material","material":"leather","amount":2 if species=="deer" else 1,"name":"Untreated Hide"},false)
            player.give_xp(3 if species=="deer" else 1)
            _notify("Hunted %s — collect and cook the meat at a campfire."%species.capitalize(),Color(.90,.74,.42))
            return
        if kind.begins_with("zombie_"):_play_zombie_sound(m,ZOMBIE_DEATH)
        player.enemies_defeated += 1
        if was_elite: player.elites_defeated += 1
        if kind.begins_with("ashfang"):
            _gathered_counts.ashfangs=int(_gathered_counts.get("ashfangs",0))+1
        elif kind=="rimecrawler":
            _gathered_counts.rimecrawlers=int(_gathered_counts.get("rimecrawlers",0))+1
        elif kind=="ashscale_basilisk":
            _gathered_counts.ashscale_basilisks=int(_gathered_counts.get("ashscale_basilisks",0))+1
        if str(profile.get("zone_id",""))=="western_reaches":
            _gathered_counts.rainward_threats=int(_gathered_counts.get("rainward_threats",0))+1
        elif str(profile.get("zone_id",""))=="stormbreak_highlands":
            _gathered_counts.stormbreak_threats=int(_gathered_counts.get("stormbreak_threats",0))+1
        elif str(profile.get("zone_id",""))=="skeld_coast":
            _gathered_counts.skeld_threats=int(_gathered_counts.get("skeld_threats",0))+1
        elif str(profile.get("zone_id",""))=="east_marches":
            _gathered_counts.marcher_threats=int(_gathered_counts.get("marcher_threats",0))+1
        _check_quest_rewards()
        var rank:int=int(m.get("rank",1))
        player.give_xp((120 if is_dragon else (12 if was_elite else 4))*rank)
        if is_dragon:
            player.hero_gold+=250;player.relic_shards+=1
            var boss_id:String=m.get("boss_id","CAVE_DRAGON")
            var key_id:="dragon_key_%s"%boss_id
            player.bag_slots.append({"id":key_id,"slot":"key","icon":9,"name":"Dragon Hoard Key","armor":0,"hp":0,"mana":0,"power":0,"description":"A massive scorched key dropped by the cave dragon. It unlocks this dragon's royal hoard."})
        if kind.begins_with("zombie_"):
            _spawn_zombie_loot(death_pos,kind,was_elite)
            if kind=="zombie_carrier":
                _burst(death_pos,Color(.36,.78,.10),4.0)
                if death_pos.distance_to(player.global_position)<4.2:_damage_player(6.0)
            if is_instance_valid(_gravebound_campaign):_gravebound_campaign.enemy_defeated(m)
            if is_instance_valid(_oathbound_campaign):_oathbound_campaign.enemy_defeated(m)
        else:
            _spawn_loot(death_pos,was_elite,rank,is_dragon)
        if kind.begins_with("ashfang"):
            _spawn_world_drop(death_pos+Vector3(.42,0,.18),{"kind":"material","material":"leather","amount":2 if was_elite else 1,"name":"Ashfang Hide"},was_elite)
        elif kind=="frost_troll":
            _spawn_world_drop(death_pos+Vector3(.48,0,.20),{"kind":"material","material":"crystal","amount":2 if was_elite else 1,"name":"Rime Crystal"},true)
            _spawn_world_drop(death_pos+Vector3(-.48,0,.12),{"kind":"material","material":"ore","amount":3 if was_elite else 2,"name":"Moraine Iron"},was_elite)
        elif kind=="rimecrawler":
            _spawn_world_drop(death_pos+Vector3(.44,0,.18),{"kind":"material","material":"chitin","amount":2 if was_elite else 1,"name":"Rime Chitin"},was_elite)
            if was_elite or rng.randf()<.42:_spawn_world_drop(death_pos+Vector3(-.44,0,.14),{"kind":"material","material":"crystal","amount":1,"name":"Crawler Ice Plate"},true)
        elif kind=="ashscale_basilisk":
            _spawn_world_drop(death_pos+Vector3(.44,0,.18),{"kind":"material","material":"leather","amount":3 if was_elite else 2,"name":"Ashscale Hide"},was_elite)
            _spawn_world_drop(death_pos+Vector3(-.44,0,.14),{"kind":"material","material":"ore","amount":2 if was_elite else 1,"name":"Basalt Iron Scale"},was_elite)
            if was_elite or rng.randf()<.22:
                _spawn_world_drop(death_pos+Vector3(0,0,-.58),{"kind":"material","material":"crystal","amount":1,"name":"Warm Emberglass"},true)
        # Counter quests award through _check_quest_rewards(). The old starter
        # payout here duplicated the Road to Crownspire reward on kill eight.
        quest_complete=bool(_quest_claimed.get("road_imps",false))
    else:
        m.anim_lock=.26
        if kind.begins_with("zombie_"):_play_zombie_sound(m,ZOMBIE_HIT)
        var reaction:="Knockdown" if amount>=48.0 and not m.get("elite",false) else ("Stagger" if amount>=24.0 else "Hit")
        _play_minion_animation(m,reaction,true)

func _tick_enemy_death(m:Dictionary,delta:float)->void:
    m.death_elapsed=float(m.get("death_elapsed",0.0))+delta
    var root:Node3D=m.node;var kind:String=m.get("kind","");var elapsed:float=m.death_elapsed
    if kind=="dragon":
        # The authored Death clip contains the full weighted body/wing collapse.
        # Retain the old procedural fall only as a fallback for a missing player.
        if not is_instance_valid(m.get("animation") as AnimationPlayer):
            var t:=clampf(elapsed/3.15,0.0,1.0);var visual:=root.get_node_or_null("DragonVisual") as Node3D
            if visual:
                visual.rotation.z=lerpf(0.0,-1.32,t*t);visual.position.y=-2.2*t
            root.scale=Vector3(1.0,lerpf(1.0,.68,t),1.0)
    elif kind=="bramble_wraith":
        var t:=clampf(elapsed/1.85,0.0,1.0);var visual:=root.get_node_or_null("WraithVisual") as Node3D
        if visual:
            visual.rotation.z=lerpf(0.0,1.38,t*t);visual.position.y=-.72*t
            visual.scale=Vector3(lerpf(1.0,.55,t),lerpf(1.0,.16,t),lerpf(1.0,.55,t))
    elif not is_instance_valid(m.get("animation") as AnimationPlayer):
        var t:=clampf(elapsed/1.25,0.0,1.0);root.rotation.z=lerpf(0.0,-1.40,t*t);root.position.y=float(m.get("floor_y",root.position.y))-.45*t

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _play_minion_animation(m: Dictionary, clip: String, force := false) -> void:
    var animation_player := m.get("animation") as AnimationPlayer
    if not is_instance_valid(animation_player) or not animation_player.has_animation(clip):
        return
    if force or animation_player.current_animation != clip:
        var ashfang_run:=clip=="Run" and str(m.get("kind","")).begins_with("ashfang")
        animation_player.speed_scale=1.24 if ashfang_run else (1.12 if clip=="Run" else 1.0)
        animation_player.play(clip, 0.14)

func _set_imp_overlay(node: Node, overlay: Material) -> void:
    if node is MeshInstance3D:
        (node as MeshInstance3D).material_overlay = overlay
    for child in node.get_children():
        _set_imp_overlay(child, overlay)

func _add_elite_imp_effect(root: Node3D) -> void:
    var ring := MeshInstance3D.new()
    ring.name = "EliteInfernalRing"
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = .42
    ring_mesh.outer_radius = .49
    ring.mesh = ring_mesh
    ring.position.y = .055
    var ring_material := StandardMaterial3D.new()
    ring_material.albedo_color = Color(1.0,.09,.01,.72)
    ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ring_material.emission_enabled = true
    ring_material.emission = Color(1.0,.018,.002)
    ring_material.emission_energy_multiplier = 3.2
    ring.material_override = ring_material
    root.add_child(ring)
    var glow := OmniLight3D.new()
    glow.name = "EliteInfernalGlow"
    glow.light_color = Color(1.0,.12,.025)
    glow.light_energy = 1.4
    glow.omni_range = 3.2
    glow.position.y = 1.0
    root.add_child(glow)

func _burst(pos: Vector3, color: Color, radius: float) -> void:
    var ring:=MeshInstance3D.new(); var cylinder:=CylinderMesh.new(); cylinder.top_radius=1; cylinder.bottom_radius=1; cylinder.height=.05; ring.mesh=cylinder
    var mat:=StandardMaterial3D.new(); mat.albedo_color=Color(color.r,color.g,color.b,.42); mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.emission_enabled=true; mat.emission=color; ring.material_override=mat; add_child(ring); ring.global_position=pos+Vector3.UP*.12
    var tween:=create_tween(); tween.tween_property(ring,"scale",Vector3(radius,.2,radius),.35); tween.parallel().tween_property(mat,"albedo_color:a",0.0,.35); tween.tween_callback(ring.queue_free)

func _combat_forward()->Vector3:
    if player.has_method("get_combat_forward"):return player.get_combat_forward()
    var visual:=player.get_node("Visual") as Node3D
    var forward:=visual.global_basis.z;forward.y=0.0;return forward.normalized()

func _cast_origin()->Vector3:
    if player.has_method("get_cast_origin"):return player.get_cast_origin()
    return player.global_position+Vector3.UP*1.38+_combat_forward()*.72

func _assisted_aim(origin:Vector3,max_range:float)->Vector3:
    var forward:=_combat_forward();var best_dir:=forward;var best_score:=-INF
    for m in minions:
        if not is_instance_valid(m.node):continue
        var to_target:Vector3=m.node.global_position+Vector3.UP*.7-origin
        var distance:=to_target.length()
        if distance<=0.01 or distance>max_range:continue
        var candidate:=to_target/distance;var facing:=forward.dot(candidate)
        if facing<.58:continue
        var score:=facing*2.0-distance/max_range
        if score>best_score:best_score=score;best_dir=candidate
    return best_dir.normalized()

func _distance_to_segment_3d(point:Vector3,a:Vector3,b:Vector3)->float:
    var segment:=b-a;var length_squared:=segment.length_squared()
    if length_squared<=0.0001:return point.distance_to(a)
    var t:=clampf((point-a).dot(segment)/length_squared,0.0,1.0)
    return point.distance_to(a+segment*t)

func _cast_flash(pos:Vector3,color:Color,size:float)->void:
    var flash:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.16;sphere.height=.32;flash.mesh=sphere
    var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=4.0;flash.material_override=mat;add_child(flash);flash.global_position=pos
    var tween:=create_tween();tween.tween_property(flash,"scale",Vector3.ONE*size,.11);tween.tween_property(flash,"scale",Vector3.ZERO,.10);tween.tween_callback(flash.queue_free)

func _impact_flash(pos:Vector3,color:Color,size:float)->void:
    _cast_flash(pos,color,maxf(1.2,size*5.0))
    _burst(_ground(pos),color,maxf(.8,size*3.0))

func _hero_action(kind: String) -> void:
    var visual:=player.get_node_or_null("Visual"); if visual and visual.has_method("play_action"): visual.play_action(kind)

func _ground(pos: Vector3) -> Vector3:
    if height_sampler.is_valid(): var sampled:Vector3=height_sampler.call(pos.x,pos.z); return Vector3(pos.x,sampled.y+.08,pos.z)
    return pos

func _clear_minions() -> void:
    for m in minions:
        if is_instance_valid(m.node): m.node.queue_free()
    minions.clear()

func admin_spawn(count: int, elite: bool) -> void:
    for i in range(count):
        if elite: _spawn_count = 4
        _spawn_minion(12.0 + float(i)*3.0,float(i)*1.7)

func admin_clear() -> void: _clear_minions()
func admin_heal() -> void: player.hp=player.max_hp; player.mana=player.max_mana
func admin_toggle_one_hit_kill()->bool:
    _admin_one_hit_kill=not _admin_one_hit_kill
    notification_requested.emit("ONE-HIT KILL %s"%("ENABLED" if _admin_one_hit_kill else "DISABLED"),Color(1.0,.72,.20))
    return _admin_one_hit_kill
func admin_toggle_god_mode()->bool:
    _admin_god_mode=not _admin_god_mode
    if _admin_god_mode:player.hp=player.max_hp
    notification_requested.emit("GOD MODE %s"%("ENABLED" if _admin_god_mode else "DISABLED"),Color(.36,.86,1.0))
    return _admin_god_mode
func admin_return() -> void: player.set_interior_mode(false);player.global_position=_ground(player.get("_spawn_position"))
func admin_add_gold(amount:int) -> void: player.hero_gold+=amount
func admin_gain_level() -> void: player.give_xp(player.next_xp)
func admin_gain_all_skills() -> void:
    for i in range(4):skill_levels[i]+=1;skill_xp[i]=0
func admin_give_materials() -> void:
    player.add_material("herbs",10)
    player.add_material("scrap",10)
    player.add_material("ore",10)
    player.add_material("essence",5)
func admin_give_potions() -> void: player.health_potions+=5; player.mana_potions+=5
func admin_equip_armor() -> void: player.equip_royal_armor()
func admin_switch_class() -> void:
    if is_instance_valid(player) and player.has_method("switch_hero_class"):player.switch_hero_class()
func admin_complete_quest() -> void:
    var baseline:=int(_quest_baselines.get("road_imps",0))
    player.enemies_defeated=maxi(player.enemies_defeated,baseline+quest_goal)
    _check_quest_rewards()

func admin_reset_quest() -> void:
    _quest_claimed.erase("road_imps")
    _quest_baselines["road_imps"]=player.enemies_defeated
    quest_complete=false
func admin_save() -> void: _save_game()
func admin_load() -> void: _load_game()

func craft_health_potion() -> bool:
    if player.herbs < 3: return false
    player.add_material("herbs",-3); player.health_potions+=1; return true

func craft_mana_potion() -> bool:
    if player.herbs < 4 or player.essence < 1: return false
    player.add_material("herbs",-4);player.add_material("essence",-1);player.mana_potions+=1;return true


func get_recipes()->Array:
    var result:Array=[]
    var gravecraft_unlocked:=is_instance_valid(_gravebound_campaign) and int(_gravebound_campaign.get("stage"))>=9
    for recipe in RECIPES:
        if str(recipe.get("unlock",""))=="gravebound" and not gravecraft_unlocked:continue
        result.append(recipe.duplicate(true))
    return result


func can_craft_recipe(recipe:Dictionary)->bool:
    if not player.can_afford_materials(recipe.get("cost",{})):return false
    var ingredient_id:String=recipe.get("ingredient_id","")
    if ingredient_id.is_empty():return true
    for item in player.bag_slots:
        if item.get("id","")==ingredient_id:return true
    return false


func craft_recipe(recipe_id:String)->String:
    var recipe:Dictionary={}
    for candidate in RECIPES:
        if candidate.get("id","")==recipe_id:
            recipe=candidate
            break
    if recipe.is_empty():return "Unknown recipe."
    var costs:Dictionary=recipe.get("cost",{})
    if not can_craft_recipe(recipe):
        if not str(recipe.get("ingredient_id","")).is_empty():return "You need a raw fish in your bag."
        return "Missing: %s"%_missing_cost_text(costs)
    if recipe.get("kind","") in ["gear","item"] and player.bag_slots.size()>=80:return "Your bag is full."
    player.spend_materials(costs)
    var ingredient_id:String=recipe.get("ingredient_id","")
    if not ingredient_id.is_empty():
        player.consume_bag_item(ingredient_id,1)
    match recipe.get("kind",""):
        "health_potion":player.health_potions+=int(recipe.get("amount",1))
        "mana_potion":player.mana_potions+=int(recipe.get("amount",1))
        "material":player.add_material(str(recipe.get("material","ore")),int(recipe.get("amount",1)))
        "gear","item":
            var crafted:=recipe.duplicate(true)
            crafted["id"]="crafted_%s_%d"%[recipe_id,Time.get_ticks_msec()]
            crafted.erase("category");crafted.erase("cost");crafted.erase("kind");crafted.erase("amount")
            player.add_bag_item(crafted)
        "cook_food":
            var food_name:=str(recipe.get("food_name","Cooked Fish"))
            player.add_bag_item({
                "id":"cooked_%s_%d"%[recipe_id,Time.get_ticks_msec()],"name":food_name,"slot":"consumable","icon":10,"use":"food",
                "visual":"cooked fish" if recipe_id=="cooked_fish" else "food bowl",
                "buff_name":recipe.get("buff_name","Well Fed"),"duration":recipe.get("duration",240.0),
                "buff_power":recipe.get("buff_power",8),"health_regen":recipe.get("health_regen",.45),
                "stamina_regen":recipe.get("stamina_regen",4.0),"heal":recipe.get("heal",24.0),
                "description":"A prepared camp meal. Double-click to eat and gain its listed recovery buff.",
            })
    _gathered_counts.crafted=int(_gathered_counts.get("crafted",0))+1
    if recipe_id=="rimecrawler_bracers":_gathered_counts.rimecraft=int(_gathered_counts.get("rimecraft",0))+1
    _check_quest_rewards()
    _notify("Crafted %s"%recipe.get("name","item"),Color(.96,.74,.25))
    return "Crafted %s."%recipe.get("name","item")


func _missing_cost_text(costs:Dictionary)->String:
    var missing:Array[String]=[]
    for kind in costs:
        var deficit:int=int(costs[kind])-player.get_material_amount(str(kind))
        if deficit>0:missing.append("%d %s"%[deficit,str(kind).capitalize()])
    return ", ".join(missing)


func get_quest_state()->Array[Dictionary]:
    var result:Array[Dictionary]=[]
    if is_instance_valid(_gravebound_campaign) and _gravebound_campaign.has_method("get_active_state"):
        result.append(_gravebound_campaign.get_active_state())
    if is_instance_valid(_oathbound_campaign) and _oathbound_campaign.has_method("get_active_state"):
        result.append(_oathbound_campaign.get_active_state())
    for definition in QUESTS:
        var quest:Dictionary=definition.duplicate(true)
        var requirement:=str(quest.get("requires",""))
        var available:=requirement.is_empty() or bool(_quest_claimed.get(requirement,false))
        _ensure_quest_baseline(quest,available)
        var current:=_quest_progress(quest) if available else 0
        quest["current"]=mini(current,int(quest.goal))
        quest["available"]=available
        quest["complete"]=available and current>=int(quest.goal)
        quest["claimed"]=bool(_quest_claimed.get(quest.id,false))
        result.append(quest)
    return result


func _quest_counter(counter:String)->int:
    if not is_instance_valid(player):return 0
    match counter:
        "kills":return player.enemies_defeated
        "elites":return player.elites_defeated
        _:return int(_gathered_counts.get(counter,0))


func _quest_progress(quest:Dictionary)->int:
    var quest_id:=str(quest.get("id",""))
    if bool(_quest_claimed.get(quest_id,false)):return int(quest.get("goal",0))
    var baseline:=int(_quest_baselines.get(quest_id,0))
    return maxi(0,_quest_counter(str(quest.get("counter","")))-baseline)


func _ensure_quest_baseline(quest:Dictionary,available:bool)->void:
    var quest_id:=str(quest.get("id",""))
    if not available or _quest_baselines.has(quest_id):return
    # Start newly revealed chapters at zero. Work done for an unrelated,
    # locked chapter no longer completes it immediately when its prerequisite
    # is turned in.
    _quest_baselines[quest_id]=_quest_counter(str(quest.get("counter","")))


func _check_quest_rewards()->void:
    for quest in QUESTS:
        var quest_id:String=quest.id
        var requirement:=str(quest.get("requires",""))
        var available:=requirement.is_empty() or bool(_quest_claimed.get(requirement,false))
        if not available:continue
        _ensure_quest_baseline(quest,true)
        if _quest_claimed.get(quest_id,false) or _quest_progress(quest)<int(quest.goal):continue
        _quest_claimed[quest_id]=true
        match quest_id:
            "road_imps":player.hero_gold+=35;player.health_potions+=1
            "field_medicine":player.hero_gold+=30;player.health_potions+=2
            "river_provision":player.hero_gold+=45;player.add_material("crystal",1)
            "winter_wood":
                player.hero_gold+=45
                player.add_bag_item({"id":"quest_forester_axe","name":"Forester's Reward Axe","slot":"mainhand","icon":8,"power":16,"armor":0,"hp":3,"mana":0,"description":"Awarded for supplying timber to the towns."})
            "first_forging":player.hero_gold+=55;player.add_material("ore",4)
            "deep_delver":player.hero_gold+=90;player.add_material("essence",2)
            "elite_hunt":player.hero_gold+=120;player.add_material("crystal",1)
            "ashfang_packs":player.hero_gold+=80;player.add_material("leather",6)
            "marcher_beacon":
                player.hero_gold+=145
                player.add_material("ore",6)
                player.add_bag_item({"id":"marchwarden_reward_lamellar","name":"Marchwarden Lamellar","slot":"chest","visual":"chest","icon":1,"armor":21,"hp":31,"mana":0,"power":5,"max_durability":215.0,"description":"Marshal Teren's basalt-iron road armor, laced over ochre leather for the exposed Dawnway."})
            "marcher_oath":
                player.hero_gold+=190
                player.add_bag_item({"id":"emberglass_reward_oath_band","name":"Emberglass Oath Band","slot":"ring_right","visual":"magic ring","ring_design":"split_band","effect":"emberpulse","icon":10,"armor":4,"hp":17,"mana":9,"power":11,"max_durability":210.0,"description":"The two witnesses' seals joined around a living bead of Embercrag glass."})
            "rainward_patrol":
                player.hero_gold+=105
                player.add_material("leather",4)
                player.add_material("resin",3)
            "rainward_reliquary":
                player.hero_gold+=135
                player.add_bag_item({"id":"rainward_patrol_signet","name":"Rainward Patrol Signet","slot":"ring_right","visual":"magic ring","ring_design":"split_band","effect":"windstep","icon":10,"armor":3,"hp":14,"mana":5,"power":6,"max_durability":170.0,"description":"The old west-road patrol mark. Its tideglass current brightens when the road ahead is open."})
            "stormbreak_beacon":
                player.hero_gold+=150
                player.add_material("ore",5)
                player.add_bag_item({"id":"stormward_patrol_mantle","name":"Stormward Patrol Mantle","slot":"shoulders","visual":"shoulders","effect":"windstep","icon":2,"armor":9,"hp":20,"mana":0,"power":5,"max_durability":180.0,"description":"The road wardens' weather-dark mantle, clasped with the three-road compact."})
            "stormbreak_choir":
                player.hero_gold+=185
                player.add_bag_item({"id":"tempest_choir_reward_band","name":"Tempest Choir Band","slot":"ring_right","visual":"magic ring","ring_design":"spiral","effect":"windstep","icon":10,"armor":5,"hp":18,"mana":12,"power":9,"max_durability":205.0,"description":"The restored highland hymn in silver and Blacktarn glass."})
            "skeld_lantern":
                player.hero_gold+=210
                player.add_material("ore",6)
                player.add_bag_item({"id":"cape_keld_reward_watchcoat","name":"Cape Keld Watchcoat","slot":"chest","visual":"chest","effect":"frostward","icon":1,"armor":17,"hp":36,"mana":6,"power":5,"max_durability":225.0,"description":"The lightkeeper's salt-dark watchcoat, warded against freezing spray."})
            "skeld_bones":
                player.hero_gold+=260
                player.add_bag_item({"id":"greywake_reward_band","name":"Greywake Lantern Band","slot":"ring_left","visual":"magic ring","ring_design":"split_band","effect":"frostward","icon":10,"armor":5,"hp":18,"mana":14,"power":9,"max_durability":220.0,"description":"The completed Whalebone canticle in sea-glass and salt-dark silver."})
            "rimecrawler_hunt":
                player.hero_gold+=140
                player.add_material("crystal",2)
                player.add_bag_item({"id":"icewatch_signet","name":"Icewatch Signet","slot":"ring_1","visual":"ring","ring_design":"split_band","effect":"frostward","icon":11,"armor":6,"hp":18,"power":4,"description":"Ysra's silver-blue signet. A cold ward shimmers across its broken-crown face."})
            "last_light_armor":player.hero_gold+=160;player.add_material("essence",2)
        if quest_id=="road_imps":quest_complete=true
        _notify("Quest complete: %s"%quest.title,Color(1.0,.78,.24))


func _build_crafting_stations()->void:
    for site in _town_service_sites():
        var center:Vector2=site.get("position",Vector2.ZERO)
        var station_point:=center+Vector2(-12.0,12.0)
        var station:=Node3D.new();station.name="%s Crafting Yard"%site.get("name","Town");add_child(station);station.global_position=_ground(Vector3(station_point.x,0,station_point.y))
        _service_solid_box(station,Vector3(0,.55,0),Vector3(4.8,1.1,2.0),Color(.28,.16,.07))
        _service_box(station,Vector3(-1.25,1.28,0),Vector3(.65,.42,1.25),Color(.24,.25,.25))
        _service_box(station,Vector3(1.25,1.12,0),Vector3(.95,.18,1.40),Color(.53,.34,.13))
        var marker:=Label3D.new();marker.text="CRAFTING YARD\nE — CRAFT";marker.position=Vector3(0,2.4,0);marker.font_size=30;marker.pixel_size=.010;marker.modulate=Color(1,.78,.30);marker.outline_size=7;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;station.add_child(marker)
        _interactables.append({"action":"craft","position":station.global_position,"radius":5.3,"label":"Use %s crafting yard"%site.get("name","town"),"node":station,"station":{"name":"%s Crafting Yard"%site.get("name","Town")}})


func _scatter_gathering_nodes()->void:
    var world_size:float=profile.get("world_size",7200.0)
    var material_cycle:=["herbs","sticks","ore","mushrooms","resin","stone"]
    for i in range(84):
        var x:=world_size*(fmod(float(i*197),89.0)/89.0-.5)*.84
        var z:=world_size*(fmod(float(i*313),97.0)/97.0-.5)*.84
        var point:=Vector2(x,z)
        if point.distance_to(safe_zone_center)<36.0:continue
        var kind:String=material_cycle[i%material_cycle.size()]
        _add_gathering_node(point,kind,i)
    for berry_index in range(26):
        var bx:=world_size*(fmod(float(berry_index*271+19),101.0)/101.0-.5)*.78
        var bz:=world_size*(fmod(float(berry_index*163+43),103.0)/103.0-.5)*.78
        if walkable_sampler.is_valid() and not walkable_sampler.call(bx,bz):continue
        _add_berry_patch(Vector2(bx,bz),berry_index)


func _add_gathering_node(point:Vector2,kind:String,index:int)->void:
    var root:=Node3D.new();root.name="Gather_%s_%d"%[kind,index];add_child(root);root.global_position=_ground(Vector3(point.x,0,point.y))
    var color:=Color(.24,.52,.16)
    if kind=="ore":color=Color(.42,.45,.49)
    elif kind=="mushrooms":color=Color(.58,.18,.16)
    elif kind=="resin":color=Color(.72,.42,.08)
    elif kind=="stone":color=Color(.48,.47,.43)
    elif kind=="sticks":color=Color(.32,.19,.08)
    if kind in ["ore","stone"]:
        _service_rock(root,Vector3(0,.28,0),Vector3(.72,.52,.64),color)
    elif kind=="sticks":
        var stick:=_service_box(root,Vector3(0,.12,0),Vector3(.12,.12,1.3),color);stick.rotation.y=float(index)*.71
    else:
        for stem in range(3):
            var offset:=Vector3(float(stem-1)*.22,.25,0)
            _service_box(root,offset,Vector3(.08,.50,.08),Color(.18,.38,.10))
            _service_rock(root,offset+Vector3(0,.34,0),Vector3(.28,.20,.28),color)
    _set_geometry_range(root,230.0)
    var material_kind:="logs" if kind=="sticks" else kind
    _interactables.append({"action":"gather","position":root.global_position,"radius":3.2,"label":"Gather %s"%kind.capitalize(),"node":root,"material":material_kind,"amount":1,"active":true})


func _add_berry_patch(point:Vector2,index:int)->void:
    var root:=Node3D.new();root.name="BerryPatch_%d"%index;add_child(root);root.global_position=_ground(Vector3(point.x,0,point.y))
    var berries:=BERRIES_SCENE.instantiate() as Node3D;berries.scale=Vector3.ONE*1.45;root.add_child(berries)
    _set_geometry_range(root,190.0)
    _interactables.append({"action":"forage_food","position":root.global_position,"radius":3.2,"label":"Pick berries","node":root,"active":true})


func _build_fishing_spots()->void:
    var spots:Array[Dictionary]=[]
    for pond in profile.get("pond_sites",[]):
        var center:Vector2=pond.get("position",Vector2.ZERO);var radius:float=pond.get("radius",70.0)*1.18
        spots.append({
            "shore":center+Vector2(radius+2.5,0),
            "water":Vector3(center.x+radius-3.0,float(pond.get("water_height",1.2))+.12,center.y),
        })
    for river in profile.get("river_corridors",[]):
        var river_points:Array=river.get("points",[])
        if river_points.size()<3:continue
        var i:=river_points.size()/2;var a:Vector2=river_points[i-1];var b:Vector2=river_points[i];var tangent:=(b-a).normalized();var normal:=Vector2(-tangent.y,tangent.x)
        var width:=float(river.get("width",48.0))
        var water_point:=b+normal*width*.38
        spots.append({
            "shore":b+normal*(width*.46+2.0),
            "water":Vector3(water_point.x,_river_surface_y(water_point.x),water_point.y),
        })
    for i in range(spots.size()):_add_fishing_spot(spots[i],i)


func _add_fishing_spot(spot:Dictionary,index:int)->void:
    var point:Vector2=spot.get("shore",Vector2.ZERO)
    var root:=Node3D.new();root.name="FishingSpot_%d"%index;add_child(root);root.global_position=_ground(Vector3(point.x,0,point.y))
    var pole:=FISHING_POLE_SCENE.instantiate() as Node3D;pole.scale=Vector3.ONE*.52;pole.rotation.z=-.18;root.add_child(pole)
    var marker:=Label3D.new();marker.text="FISHING SPOT\nE - CAST  |  E ON BITE - REEL";marker.position=Vector3(0,2.2,0);marker.font_size=24;marker.pixel_size=.009;marker.modulate=Color(.72,.90,1.0);marker.outline_size=7;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;root.add_child(marker)
    _set_geometry_range(root,220.0)
    _interactables.append({"action":"fish","position":root.global_position,"water_position":spot.get("water",root.global_position),"radius":3.0,"label":"Fish here","node":root,"active":true})


func _river_surface_y(x:float)->float:
    var grade:=2.4+x*.00042+sin(x*.003)*.08
    grade+=smoothstep(-1195.0,-1125.0,x)*3.2
    grade+=smoothstep(2005.0,2075.0,x)*2.6
    return grade-2.8+float(profile.get("river_water_lift",1.35))


func _register_house_doors()->void:
    for door_node in get_tree().get_nodes_in_group("interactive_house_door"):
        if not door_node is Node3D:continue
        var door:=door_node as Node3D
        _interactables.append({"action":"door","position":door.global_position,"radius":3.8,"label":"Open door","node":door,"open":false,"active":true})


func refresh_populated_world_registries()->void:
    # Main configures gameplay before staged world dressing so the loading
    # screen can advance. Rebuild the registries once those authored nodes and
    # metadata exist, while retaining non-door gameplay interactions.
    _interactables=_interactables.filter(func(interaction:Dictionary)->bool:
        return str(interaction.get("action","")) not in ["door","mount_horse"]
    )
    _register_house_doors()
    _register_rideable_horses()
    _configure_harvestable_world_trees()
    _configure_local_prop_collisions()


func _register_rideable_horses()->void:
    for horse_value in get_tree().get_nodes_in_group("rideable_horse"):
        if not horse_value is Node3D:continue
        var horse:=horse_value as Node3D
        var horse_name:=str(horse.get_meta("horse_name","Riverwatch Courser"))
        _interactables.append({
            "action":"mount_horse","position":horse.global_position,"radius":1.8,
            "label":"Ride %s"%horse_name,"node":horse,
            "active":not bool(horse.get_meta("mounted",false)),
        })


func _refresh_horse_interaction_states()->void:
    for interaction in _interactables:
        if str(interaction.get("action",""))!="mount_horse":continue
        var horse:=interaction.get("node") as Node3D
        interaction.active=is_instance_valid(horse) and not bool(horse.get_meta("mounted",false))
        if is_instance_valid(horse):interaction.position=horse.global_position


func _set_geometry_range(root:Node,range_end:float)->void:
    var stack:Array[Node]=[root]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if node is GeometryInstance3D:
            node.visibility_range_end=range_end
            node.visibility_range_end_margin=minf(32.0,range_end*.12)


func _batch_static_service_geometry()->void:
    # Dungeon shells and service architecture use precise individual collision
    # boxes, but their visuals do not need one draw call per wall or floor
    # piece. Batch static BoxMesh visuals inside each streamed top-level root;
    # doors, chests, secret walls, enemies and other moving nodes stay separate.
    var dynamic_roots:Dictionary={}
    for enemy in minions:
        var enemy_node:=enemy.get("node") as Node
        if is_instance_valid(enemy_node):dynamic_roots[enemy_node.get_instance_id()]=true
    for portal in _portals:
        for key in ["door","chest","lid","marker","node"]:
            var portal_node:=portal.get(key) as Node
            if is_instance_valid(portal_node):dynamic_roots[portal_node.get_instance_id()]=true
    for interaction in _interactables:
        var interaction_node:=interaction.get("node") as Node
        if is_instance_valid(interaction_node):dynamic_roots[interaction_node.get_instance_id()]=true
    for child in get_children():
        if child is Node3D and not dynamic_roots.has(child.get_instance_id()):
            _batch_static_service_boxes(child as Node3D,dynamic_roots)


func _batch_static_service_boxes(scope:Node3D,dynamic_roots:Dictionary)->void:
    var groups:Dictionary={}
    var materials:Dictionary={}
    var shadow_modes:Dictionary={}
    var candidates:Array[MeshInstance3D]=[]
    var stack:Array[Node]=[scope]
    while not stack.is_empty():
        var node:Node=stack.pop_back()
        for child in node.get_children():stack.append(child)
        if not node is MeshInstance3D:continue
        var mesh_instance:=node as MeshInstance3D
        if not mesh_instance.mesh is BoxMesh or mesh_instance.material_override==null:continue
        if _service_visual_is_dynamic(mesh_instance,scope,dynamic_roots):continue
        var box:=mesh_instance.mesh as BoxMesh
        var local_transform:=scope.global_transform.affine_inverse()*mesh_instance.global_transform
        local_transform=local_transform*Transform3D(Basis.IDENTITY.scaled(box.size),Vector3.ZERO)
        var shadow_mode:=int(mesh_instance.cast_shadow)
        var material:Material=mesh_instance.material_override
        var key:="%d|%d"%[material.get_instance_id(),shadow_mode]
        if not groups.has(key):groups[key]=[]
        groups[key].append(local_transform)
        materials[key]=material
        shadow_modes[key]=shadow_mode
        candidates.append(mesh_instance)
    if candidates.size()<12:return
    for candidate in candidates:
        var parent:=candidate.get_parent()
        if parent:
            parent.remove_child(candidate)
            candidate.free()
    var unit_box:=BoxMesh.new();unit_box.size=Vector3.ONE
    var batch_index:=0
    for key in groups:
        var transforms:Array=groups[key]
        var multimesh:=MultiMesh.new()
        multimesh.transform_format=MultiMesh.TRANSFORM_3D
        multimesh.instance_count=transforms.size()
        multimesh.mesh=unit_box
        var buffer:=PackedFloat32Array()
        buffer.resize(transforms.size()*12)
        for transform_index in range(transforms.size()):
            var transform:Transform3D=transforms[transform_index]
            var basis:=transform.basis
            var offset:=transform_index*12
            buffer[offset+0]=basis.x.x;buffer[offset+1]=basis.y.x;buffer[offset+2]=basis.z.x;buffer[offset+3]=transform.origin.x
            buffer[offset+4]=basis.x.y;buffer[offset+5]=basis.y.y;buffer[offset+6]=basis.z.y;buffer[offset+7]=transform.origin.y
            buffer[offset+8]=basis.x.z;buffer[offset+9]=basis.y.z;buffer[offset+10]=basis.z.z;buffer[offset+11]=transform.origin.z
        multimesh.buffer=buffer
        var instance:=MultiMeshInstance3D.new()
        instance.name="StaticServiceBatch_%d"%batch_index
        instance.multimesh=multimesh
        instance.material_override=materials[key]
        instance.cast_shadow=int(shadow_modes[key])
        scope.add_child(instance)
        batch_index+=1


func _service_visual_is_dynamic(mesh:MeshInstance3D,scope:Node,dynamic_roots:Dictionary)->bool:
    var ancestor:Node=mesh
    while ancestor and ancestor!=scope:
        if dynamic_roots.has(ancestor.get_instance_id()):return true
        if ancestor!=mesh and ancestor.get_script()!=null:return true
        var lower_name:=str(ancestor.name).to_lower()
        for keyword in ["door","gate","chest","secret","key","portal","rotor"]:
            if keyword in lower_name:return true
        ancestor=ancestor.get_parent()
    return false


func _configure_harvestable_world_trees()->void:
    _forest_trees.clear();_tree_buckets.clear();_nearby_world_tree={}
    var world_root:=get_parent().get_node_or_null("WorldRoot")
    if not world_root:return
    for source_root in _world_population_roots(world_root,["PropsRoot","TownRoot"]):
        for tree_data in source_root.get_meta("harvestable_tree_registry",[]):
            if not tree_data is Dictionary:continue
            var tree:Dictionary=tree_data
            _forest_trees.append(tree)
            var position:Vector3=tree.get("position",Vector3.ZERO)
            var key:=_tree_bucket_key(position)
            if not _tree_buckets.has(key):_tree_buckets[key]=[]
            _tree_buckets[key].append(tree)


func _configure_local_prop_collisions()->void:
    _rock_collision_registry.clear()
    _prop_collision_buckets.clear()
    _mineable_rocks.clear()
    _mineable_rock_buckets.clear()
    _nearby_world_rock={}
    var world_root:=get_parent().get_node_or_null("WorldRoot")
    if world_root:
        for props_root in _world_population_roots(world_root,["PropsRoot"]):
            _rock_collision_registry.append_array(props_root.get_meta("collision_prop_registry",[]))
            for rock_value in props_root.get_meta("mineable_rock_registry",[]):
                if not rock_value is Dictionary:continue
                var rock:Dictionary=rock_value
                _mineable_rocks.append(rock)
                var rock_key:=_tree_bucket_key(rock.get("position",Vector3.ZERO))
                if not _mineable_rock_buckets.has(rock_key):_mineable_rock_buckets[rock_key]=[]
                _mineable_rock_buckets[rock_key].append(rock)
    for prop_value in _rock_collision_registry:
        if not prop_value is Dictionary:continue
        var prop:Dictionary=prop_value
        var prop_key:=_tree_bucket_key(prop.get("position",Vector3.ZERO))
        if not _prop_collision_buckets.has(prop_key):_prop_collision_buckets[prop_key]=[]
        _prop_collision_buckets[prop_key].append(prop)
    if not is_instance_valid(_local_prop_collision_body):
        _local_prop_collision_body=StaticBody3D.new()
        _local_prop_collision_body.name="LocalPropCollisionPool"
        _local_prop_collision_body.collision_layer=1
        _local_prop_collision_body.set_meta("always_streamed",true)
        add_child(_local_prop_collision_body)
        _local_prop_collision_shapes.clear()
        for i in range(128):
            var collision:=CollisionShape3D.new()
            collision.disabled=true
            _local_prop_collision_body.add_child(collision)
            _local_prop_collision_shapes.append(collision)
    _reset_local_prop_collision_slots()
    _refresh_local_prop_collisions(true)


func _world_population_roots(world_root:Node,root_names:Array[String])->Array[Node]:
    var result:Array[Node]=[]
    for root_name in root_names:
        var direct:=world_root.get_node_or_null(root_name)
        if direct!=null:result.append(direct)
    var streamed_regions:=world_root.get_node_or_null("StreamedRegions")
    if streamed_regions!=null:
        for region in streamed_regions.get_children():
            for root_name in root_names:
                var nested:=region.get_node_or_null(root_name)
                if nested!=null:result.append(nested)
    return result


func _reset_local_prop_collision_slots()->void:
    _active_prop_collision_slots.clear()
    _prop_collision_slot_keys.clear()
    _prop_collision_slot_keys.resize(_local_prop_collision_shapes.size())
    for i in range(_local_prop_collision_shapes.size()):
        _prop_collision_slot_keys[i]=""
        var collision:=_local_prop_collision_shapes[i]
        if not collision.disabled:collision.disabled=true
    _active_prop_collision_signature=""


func _refresh_local_prop_collisions(force:bool=false)->void:
    if not is_instance_valid(_local_prop_collision_body) or not is_instance_valid(player):return
    # These props are static. Rebuilding every pooled physics shape 12+ times a
    # second produced visible walking hitches even when the nearby set had not
    # changed. Sample after meaningful travel, then touch PhysicsServer only if
    # a prop actually entered or left the active collision bubble.
    var player_position:=player.global_position
    if not force and is_finite(_last_prop_collision_refresh_position.x):
        var travel:=Vector2(
            player_position.x-_last_prop_collision_refresh_position.x,
            player_position.z-_last_prop_collision_refresh_position.z
        )
        if travel.length_squared()<LOCAL_PROP_COLLISION_REFRESH_DISTANCE*LOCAL_PROP_COLLISION_REFRESH_DISTANCE:return
    _last_prop_collision_refresh_position=player_position
    var candidates:Array[Dictionary]=[]
    var center_key:=_tree_bucket_key(player_position)
    for offset_x in range(-1,2):
        for offset_z in range(-1,2):
            for tree_value in _tree_buckets.get(center_key+Vector2i(offset_x,offset_z),[]):
                var tree:Dictionary=tree_value
                if not tree.get("active",true):continue
                var position:Vector3=tree.get("position",Vector3.ZERO)
                var distance:=Vector2(position.x-player_position.x,position.z-player_position.z).length_squared()
                if distance<=22.0*22.0:
                    candidates.append({"kind":"tree","position":position,"scale":float(tree.get("scale",1.0)),"distance":distance})
    for offset_x in range(-1,2):
        for offset_z in range(-1,2):
            for prop_value in _prop_collision_buckets.get(center_key+Vector2i(offset_x,offset_z),[]):
                var prop:Dictionary=prop_value
                if not prop.get("active",true):continue
                var position:Vector3=prop.get("position",Vector3.ZERO)
                var distance:=Vector2(position.x-player_position.x,position.z-player_position.z).length_squared()
                if distance<=28.0*28.0:
                    candidates.append({"kind":str(prop.get("kind","rock")),"position":position,"radius":float(prop.get("radius",1.0)),"distance":distance})
    candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.distance)<float(b.distance))
    var desired_candidates:Dictionary={}
    var desired_keys:Array[String]=[]
    var active_count:=mini(candidates.size(),_local_prop_collision_shapes.size())
    for i in range(active_count):
        var candidate:=candidates[i]
        var key:=_prop_collision_key(candidate)
        desired_candidates[key]=candidate
        desired_keys.append(key)
    desired_keys.sort()
    var signature:="|".join(PackedStringArray(desired_keys))
    if not force and signature==_active_prop_collision_signature:return
    var started_usec:=Time.get_ticks_usec()
    var physics_changes:=0
    _active_prop_collision_signature=signature
    var removed_keys:Array[String]=[]
    for key_value in _active_prop_collision_slots.keys():
        var key:=str(key_value)
        if not desired_candidates.has(key):removed_keys.append(key)
    for key in removed_keys:
        var slot:=int(_active_prop_collision_slots.get(key,-1))
        _active_prop_collision_slots.erase(key)
        if slot<0 or slot>=_local_prop_collision_shapes.size():continue
        _prop_collision_slot_keys[slot]=""
        var collision:=_local_prop_collision_shapes[slot]
        if not collision.disabled:
            collision.disabled=true
            physics_changes+=1
    for candidate in candidates.slice(0,active_count):
        var key:=_prop_collision_key(candidate)
        if _active_prop_collision_slots.has(key):continue
        var slot:=_prop_collision_slot_keys.find("")
        if slot<0:break
        var collision:=_local_prop_collision_shapes[slot]
        var position:Vector3=candidate.position
        if candidate.kind=="tree":
            var scale_value:=clampf(float(candidate.scale),.58,1.7)
            var tree_shape:=collision.shape as CylinderShape3D
            if tree_shape==null:
                tree_shape=CylinderShape3D.new()
                collision.shape=tree_shape
                physics_changes+=1
            tree_shape.radius=.38*scale_value
            tree_shape.height=4.8*scale_value
            position.y+=tree_shape.height*.5
        else:
            var rock_shape:=collision.shape as SphereShape3D
            if rock_shape==null:
                rock_shape=SphereShape3D.new()
                collision.shape=rock_shape
                physics_changes+=1
            rock_shape.radius=maxf(.55,float(candidate.radius))
        collision.position=position
        physics_changes+=1
        if collision.disabled:
            collision.disabled=false
            physics_changes+=1
        _active_prop_collision_slots[key]=slot
        _prop_collision_slot_keys[slot]=key
    _collision_refresh_sequence+=1
    _last_collision_refresh={
        "sequence":_collision_refresh_sequence,
        "candidates":active_count,
        "physics_changes":physics_changes,
        "apply_ms":float(Time.get_ticks_usec()-started_usec)/1000.0,
        "at_msec":Time.get_ticks_msec(),
    }


func _prop_collision_key(candidate:Dictionary)->String:
    var position:Vector3=candidate.get("position",Vector3.ZERO)
    return "%s:%.3f:%.3f:%.3f"%[candidate.get("kind","prop"),position.x,position.y,position.z]


func _tree_bucket_key(position:Vector3)->Vector2i:
    return Vector2i(floori(position.x/56.0),floori(position.z/56.0))


func _find_nearby_world_tree()->Dictionary:
    var center_key:=_tree_bucket_key(player.global_position)
    var nearest:Dictionary={}
    var nearest_distance:=INF
    for offset_x in range(-1,2):
        for offset_z in range(-1,2):
            var key:=center_key+Vector2i(offset_x,offset_z)
            for tree_data in _tree_buckets.get(key,[]):
                var tree:Dictionary=tree_data
                if not tree.get("active",true):continue
                var position:Vector3=tree.get("position",Vector3.ZERO)
                var radius:=5.0+clampf(float(tree.get("scale",1.0)),.5,1.8)
                var distance:=Vector2(position.x-player.global_position.x,position.z-player.global_position.z).length_squared()
                if distance<=radius*radius and distance<nearest_distance:
                    nearest_distance=distance
                    nearest=tree
    return nearest


func _find_nearby_world_rock()->Dictionary:
    var center_key:=_tree_bucket_key(player.global_position)
    var nearest:Dictionary={}
    var nearest_distance:=INF
    for offset_x in range(-1,2):
        for offset_z in range(-1,2):
            for rock_value in _mineable_rock_buckets.get(center_key+Vector2i(offset_x,offset_z),[]):
                var rock:Dictionary=rock_value
                if not rock.get("active",true):continue
                var position:Vector3=rock.get("position",Vector3.ZERO)
                var radius:=clampf(float(rock.get("radius",2.0))+2.7,4.4,9.2)
                var distance:=Vector2(position.x-player.global_position.x,position.z-player.global_position.z).length_squared()
                if distance<=radius*radius and distance<nearest_distance:
                    nearest_distance=distance
                    nearest=rock
    return nearest


func _set_world_tree_visible(tree:Dictionary,visible_value:bool)->void:
    for node_value in tree.get("nodes",[]):
        var tree_node:=node_value as GeometryInstance3D
        if is_instance_valid(tree_node):tree_node.visible=visible_value
    for part_value in tree.get("batched_parts",[]):
        var part:Dictionary=part_value
        if part.is_empty():continue
        var instance:=part.get("instance") as MultiMeshInstance3D
        var index:int=int(part.get("index",-1))
        if not is_instance_valid(instance) or instance.multimesh==null or index<0:continue
        var transform:Transform3D=part.get("transform",Transform3D.IDENTITY)
        if not visible_value:
            # Keep the hidden instance at its original origin. Sending one
            # tree thousands of metres underground expanded the MultiMesh AABB
            # and caused the renderer to cull its entire surrounding forest
            # chunk. A tiny valid basis hides just this tree without changing
            # the batch bounds.
            transform.basis=Basis.IDENTITY.scaled(Vector3.ONE*.0001)
        _write_multimesh_transform(instance.multimesh,index,transform)


func _write_multimesh_transform(multimesh:MultiMesh,index:int,transform:Transform3D)->void:
    # Updating the packed buffer is reliable in both rendered and headless
    # runs; some backends defer set_instance_transform() until a draw pass.
    var stride:=12+(4 if multimesh.use_colors else 0)+(4 if multimesh.use_custom_data else 0)
    var offset:=index*stride
    var buffer:=multimesh.buffer
    if index<0 or offset+11>=buffer.size():return
    var basis:=transform.basis
    buffer[offset+0]=basis.x.x;buffer[offset+1]=basis.y.x;buffer[offset+2]=basis.z.x;buffer[offset+3]=transform.origin.x
    buffer[offset+4]=basis.x.y;buffer[offset+5]=basis.y.y;buffer[offset+6]=basis.z.y;buffer[offset+7]=transform.origin.y
    buffer[offset+8]=basis.x.z;buffer[offset+9]=basis.y.z;buffer[offset+10]=basis.z.z;buffer[offset+11]=transform.origin.z
    multimesh.buffer=buffer


func _activate_world_tree(tree:Dictionary)->void:
    if not tree.get("active",true):return
    if not player.has_method("has_axe_equipped") or not player.has_axe_equipped():
        _notify("Open I, double-click Axe into Mainhand, then press E at any tree",Color(1.0,.64,.24))
        return
    _hero_action("chop")
    tree.hits=int(tree.get("hits",0))+1
    _notify("Woodcutting %d / 3 — press E again"%tree.hits,Color(.86,.67,.32))
    if tree.hits<3:return
    tree.active=false
    _nearby_world_tree={}
    _set_world_tree_visible(tree,false)
    _refresh_local_prop_collisions(true)
    var position:Vector3=tree.get("position",Vector3.ZERO)
    _spawn_felled_tree_visual(position,clampf(float(tree.get("scale",1.0)),.68,1.35),int(roundi(position.x+position.z)))
    get_tree().create_timer(90.0).timeout.connect(func():
        tree.hits=0;tree.active=true
        _set_world_tree_visible(tree,true)
        _refresh_local_prop_collisions(true))


func _set_world_rock_visible(rock:Dictionary,visible_value:bool)->void:
    var collision:=rock.get("collision_shape") as CollisionShape3D
    if is_instance_valid(collision):collision.set_deferred("disabled",not visible_value)
    var part:Dictionary=rock.get("batched_part",{})
    if part.is_empty():return
    var instance:=part.get("instance") as MultiMeshInstance3D
    var index:=int(part.get("index",-1))
    if not is_instance_valid(instance) or instance.multimesh==null or index<0:return
    var transform:Transform3D=part.get("transform",Transform3D.IDENTITY)
    if not visible_value:transform.basis=Basis.IDENTITY.scaled(Vector3.ONE*.0001)
    _write_multimesh_transform(instance.multimesh,index,transform)


func _activate_world_rock(rock:Dictionary)->void:
    if not rock.get("active",true):return
    if not player.has_method("has_pickaxe_equipped") or not player.has_pickaxe_equipped():
        _notify("Equip the Pickaxe in Mainhand, then press E beside the rock",Color(1.0,.68,.28))
        return
    _hero_action("mine")
    rock.hits=int(rock.get("hits",0))+1
    _notify("Mining %d / 3"%rock.hits,Color(.74,.82,.92))
    if rock.hits<3:return
    rock.active=false
    _nearby_world_rock={}
    _set_world_rock_visible(rock,false)
    _refresh_local_prop_collisions(true)
    var ground:Vector3=rock.get("ground_position",rock.get("position",Vector3.ZERO))
    var ore_name:String=rock.get("ore_name","Iron Ore")
    var ore_color:Color=rock.get("ore_color",Color(.35,.37,.38))
    _spawn_mined_rock_break(ground,float(rock.get("scale",3.0)),ore_color)
    _spawn_world_drop(ground+Vector3(-.7,0,.2),{"kind":"material","material":"ore","amount":1,"name":ore_name,"ore_color":ore_color})
    _spawn_world_drop(ground+Vector3(.75,0,-.25),{"kind":"material","material":"stone","amount":1,"name":"Broken Stone"})
    _notify("Rock broken - pick up the ore and stone with E",Color(.74,1.0,.58))
    get_tree().create_timer(150.0).timeout.connect(func():
        rock.hits=0
        rock.active=true
        _set_world_rock_visible(rock,true)
        _refresh_local_prop_collisions(true))


func _spawn_mined_rock_break(position:Vector3,rock_scale:float,ore_color:Color=Color(.35,.37,.38))->void:
    var fragments:=Node3D.new()
    fragments.name="MinedRockFragments"
    add_child(fragments)
    fragments.global_position=position
    for i in range(7):
        var angle:=TAU*float(i)/7.0
        var distance:=.35+float(i%3)*.32
        var size:=clampf(rock_scale*.13,0.32,.82)*(1.0+float(i%2)*.22)
        _service_rock(
            fragments,
            Vector3(cos(angle)*distance,size*.42,sin(angle)*distance),
            Vector3(size*1.25,size,size),
            ore_color.darkened(.14).lightened(float(i%3)*.055)
        )
    var tween:=create_tween()
    tween.tween_property(fragments,"rotation:y",.48,.34)
    tween.parallel().tween_property(fragments,"scale",Vector3.ONE*1.08,.34)
    tween.tween_interval(.55)
    tween.tween_property(fragments,"scale",Vector3.ZERO,.38)
    tween.tween_callback(fragments.queue_free)


func _spawn_felled_tree_visual(position:Vector3,tree_scale:float,seed_value:int)->void:
    var falling_tree:=Node3D.new();falling_tree.name="FallingHarvestTree";add_child(falling_tree);falling_tree.global_position=position
    var authored:=CHOPPABLE_TREE_SCENE.instantiate() as Node3D
    authored.scale=Vector3.ONE*tree_scale
    falling_tree.add_child(authored)
    var fall_direction:=1.0 if absi(seed_value)%2==0 else -1.0
    var tween:=create_tween();tween.tween_property(falling_tree,"rotation:z",fall_direction*1.42,.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tween.tween_callback(func():
        _spawn_felled_logs(position)
        get_tree().create_timer(FELLED_TREE_LINGER_SECONDS).timeout.connect(func():
            if is_instance_valid(falling_tree):falling_tree.queue_free())
        _notify("Tree felled — press E near each log to pick it up",Color(.72,1.0,.50)))


func _spawn_felled_logs(position:Vector3)->void:
    var offsets:=[Vector3(-1.05,0,-.22),Vector3(.05,0,.40),Vector3(1.08,0,-.12)]
    for offset in offsets:
        _spawn_world_drop(position+offset,{"kind":"material","material":"logs","amount":1,"name":"Fallen Log"})


func _activate_interactable(data:Dictionary)->void:
    if not data.get("active",true):return
    match data.get("action",""):
        "gravebound_story":
            if is_instance_valid(_gravebound_campaign):_gravebound_campaign.activate(data)
        "oathbound_story":
            if is_instance_valid(_oathbound_campaign):_oathbound_campaign.activate(data)
        "mount_horse":
            var horse:=data.get("node") as Node3D
            if not is_instance_valid(horse):return
            if player.has_method("mount_horse") and player.mount_horse(horse):
                data.active=false
                _nearby_interactable={}
                var horse_name:=str(horse.get_meta("horse_name","Riverwatch Courser"))
                _notify("Mounted %s — Shift gallops, E dismounts"%horse_name,Color(.88,.75,.42))
        "craft":crafting_requested.emit(data.get("station",{}))
        "campfire":
            camp_rest()
            crafting_requested.emit(data.get("station",{"name":"Travel Campfire","kind":"cooking"}))
            _notify("Rested by the fire",Color(1.0,.72,.34))
        "door":
            var door:Node3D=data.get("node")
            if not is_instance_valid(door):return
            var opening:bool=not bool(data.get("open",false))
            var player_local:=door.to_local(player.global_position)
            var door_width:=float(door.get_meta("door_width",2.25))
            # Refuse to close a solid leaf through the hero. The player can
            # step clear and press E again instead of becoming wedged in the
            # collision while the tween completes.
            if not opening and player_local.x>-.45 and player_local.x<door_width+.45 and absf(player_local.z)<1.15:
                _notify("Step clear of the doorway before closing it",Color(1.0,.76,.32))
                return
            data.open=opening
            door.set_meta("door_open",opening)
            if opening:
                # Swing into the side opposite the player. The old fixed
                # direction drove many front-facing doors directly through a
                # player standing at the interaction point.
                data["open_angle"]=1.62 if player_local.z>=0.0 else -1.62
            var target_angle:=float(data.get("open_angle",1.62)) if opening else 0.0
            var tween:=create_tween();tween.tween_property(door,"rotation:y",target_angle,.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
            data.label="Close door" if opening else "Open door"
        "secret_wall":
            var secret_wall:Node3D=data.get("node")
            if not is_instance_valid(secret_wall):return
            data.active=false
            var secret_marker:Node=data.get("marker")
            if is_instance_valid(secret_marker):secret_marker.visible=false
            var secret_tween:=create_tween();secret_tween.tween_property(secret_wall,"position:y",secret_wall.position.y-6.5,.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
            _notify("A concealed passage opens",Color(.80,.68,.42))
        "read_lore":
            lore_requested.emit(str(data.get("title","Recovered Record")),_lore_entry_text(str(data.get("entry",""))))
        "hidden_cache":
            _open_hidden_cache(data)
        "gather":
            var material_kind:String=data.get("material","herbs")
            var amount:int=int(data.get("amount",1))
            player.add_material(material_kind,amount)
            if material_kind in _gathered_counts:_gathered_counts[material_kind]=int(_gathered_counts[material_kind])+amount
            data.active=false
            var node:Node3D=data.get("node")
            if is_instance_valid(node):node.visible=false
            _notify("Picked up %s x%d"%[material_kind.capitalize(),amount],Color(.66,1.0,.42))
            _check_quest_rewards()
            get_tree().create_timer(75.0).timeout.connect(func():
                data.active=true
                if is_instance_valid(node):node.visible=true)
        "forage_food":
            var berry_node:Node3D=data.get("node")
            if not player.add_bag_item({"id":"berries_%d"%Time.get_ticks_msec(),"name":"Berries","slot":"consumable","icon":10,"use":"food","buff_name":"Forager's Vigor","duration":75.0,"buff_power":2,"health_regen":.12,"stamina_regen":1.2,"heal":6.0,"description":"Fresh berries. Double-click to eat: heal 6 and gain a small short food buff."}):
                _notify("Your bag is full",Color(1,.45,.25));return
            data.active=false
            if is_instance_valid(berry_node):berry_node.visible=false
            _notify("Picked berries - double-click them in I to eat",Color(.72,1.0,.52))
            get_tree().create_timer(90.0).timeout.connect(func():
                data.active=true
                if is_instance_valid(berry_node):berry_node.visible=true)
        "fish":
            if not player.has_method("has_fishing_pole_equipped") or not player.has_fishing_pole_equipped():
                _notify("Equip the Fishing Pole from I, then press E here",Color(.70,.88,1.0));return
            if not _can_cast_fishing(data):
                _notify("Move closer to the water before casting",Color(.70,.88,1.0));return
            _start_fishing(data)


func _fishing_cast_distance(data:Dictionary)->float:
    if not is_instance_valid(player):return INF
    var water:Vector3=data.get("water_position",Vector3.INF)
    if not water.is_finite():return INF
    return Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(water.x,water.z))


func _can_cast_fishing(data:Dictionary)->bool:
    return _fishing_cast_distance(data)<=FISHING_MAX_CAST_DISTANCE


func _start_fishing(data:Dictionary)->void:
    if not _can_cast_fishing(data):
        _notify("Move closer to the water before casting",Color(.70,.88,1.0))
        return
    data.active=false
    _fishing_active=true
    _fishing_phase="waiting"
    _fishing_timer=rng.randf_range(1.5,3.4)
    _fishing_elapsed=0.0
    _fishing_spot=data
    _fishing_target=data.get("water_position",player.global_position+_combat_forward()*7.0)
    _spawn_fishing_visual()
    _hero_action("fish")
    _notify("Line cast - wait for the BITE, then press E to reel",Color(.65,.86,1.0))


func _tick_fishing(delta:float)->void:
    if not _fishing_active:return
    _fishing_elapsed+=delta
    _animate_fishing_visual()
    _fishing_timer-=delta
    if _fishing_timer>0.0:return
    if _fishing_phase=="waiting":
        _fishing_phase="bite"
        _fishing_timer=1.45
        if is_instance_valid(_fishing_fish_shadow):_fishing_fish_shadow.visible=true
        _notify("BITE!  PRESS E NOW",Color(1.0,.82,.22))
    elif _fishing_phase=="bite":
        _finish_fishing(false,"The fish got away. Cast again with E.")


func _reel_fishing()->void:
    if _fishing_phase=="waiting":
        _finish_fishing(false,"Too soon - the empty hook came back.")
        return
    if _fishing_phase!="bite":return
    if _fishing_timer<.18:
        _finish_fishing(false,"Too late - the fish slipped off the hook.")
        return
    _hero_action("fish")
    var fish_item:={"id":"raw_fish","stack_key":"item:raw_fish","stackable":true,"quantity":1,"name":"Raw Fish","slot":"consumable","visual":"fish","icon":10,"use":"food","buff_name":"Fresh Catch","duration":110.0,"buff_power":4,"health_regen":.20,"stamina_regen":2.0,"heal":10.0,"description":"A fresh fish. Double-click to eat it raw, or cook it at a town crafting yard for a much stronger meal."}
    if not player.add_bag_item(fish_item):
        _finish_fishing(false,"Your bag is full; make space before fishing.")
        return
    _gathered_counts.fish=int(_gathered_counts.get("fish",0))+1
    _check_quest_rewards()
    _finish_fishing(true,"Caught Raw Fish - added to your bag")


func _finish_fishing(success:bool,message:String)->void:
    var finished_spot:=_fishing_spot
    _fishing_active=false
    _fishing_phase=""
    _fishing_timer=0.0
    _fishing_elapsed=0.0
    _fishing_spot={}
    if is_instance_valid(_fishing_visual):
        var visual_to_remove:=_fishing_visual
        var tween:=create_tween()
        tween.tween_property(visual_to_remove,"scale",Vector3.ZERO,.16)
        tween.tween_callback(visual_to_remove.queue_free)
    _fishing_visual=null;_fishing_bobber=null;_fishing_line=null;_fishing_ripple=null;_fishing_fish_shadow=null
    _notify(message,Color(.72,1.0,.72) if success else Color(1.0,.68,.34))
    get_tree().create_timer(2.0 if success else .65).timeout.connect(func():finished_spot.active=true)


func _spawn_fishing_visual()->void:
    if is_instance_valid(_fishing_visual):_fishing_visual.queue_free()
    _fishing_visual=Node3D.new()
    _fishing_visual.name="FishingCastVisual"
    _fishing_visual.set_meta("always_streamed",true)
    add_child(_fishing_visual)
    _fishing_bobber=Node3D.new()
    _fishing_bobber.name="WaterBobber"
    _fishing_visual.add_child(_fishing_bobber)
    _service_rock(_fishing_bobber,Vector3(0,.07,0),Vector3(.24,.34,.24),Color(.92,.89,.74))
    _service_rock(_fishing_bobber,Vector3(0,.25,0),Vector3(.25,.24,.25),Color(.78,.09,.045))
    _service_box(_fishing_bobber,Vector3(0,.47,0),Vector3(.035,.45,.035),Color(.16,.11,.06))
    _fishing_ripple=MeshInstance3D.new()
    var ripple_mesh:=TorusMesh.new();ripple_mesh.inner_radius=.44;ripple_mesh.outer_radius=.49;ripple_mesh.rings=16;ripple_mesh.ring_segments=8
    _fishing_ripple.mesh=ripple_mesh
    var ripple_material:=_service_material(Color(.72,.92,.96,.88)).duplicate() as StandardMaterial3D
    ripple_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
    _fishing_ripple.material_override=ripple_material
    _fishing_visual.add_child(_fishing_ripple)
    _fishing_line=MeshInstance3D.new()
    _fishing_line.name="FishingLine"
    _fishing_line.material_override=_service_material(Color(.78,.81,.72))
    _fishing_visual.add_child(_fishing_line)
    _fishing_fish_shadow=MeshInstance3D.new()
    var fish_mesh:=SphereMesh.new();fish_mesh.radius=.34;fish_mesh.height=.92;fish_mesh.radial_segments=8;fish_mesh.rings=4
    _fishing_fish_shadow.mesh=fish_mesh
    _fishing_fish_shadow.scale=Vector3(1.55,.20,.62)
    _fishing_fish_shadow.material_override=_service_material(Color(.055,.13,.14,.58))
    _fishing_fish_shadow.visible=false
    _fishing_visual.add_child(_fishing_fish_shadow)
    _animate_fishing_visual()


func _animate_fishing_visual()->void:
    if not is_instance_valid(_fishing_bobber):return
    var bobber_position:=_fishing_target
    if _fishing_elapsed<.58:
        var cast_t:=clampf(_fishing_elapsed/.58,0.0,1.0)
        var cast_origin:Vector3=player.get_fishing_line_origin() if player.has_method("get_fishing_line_origin") else player.global_position+Vector3.UP*1.35
        bobber_position=cast_origin.lerp(_fishing_target,cast_t)+Vector3.UP*sin(cast_t*PI)*2.25
    elif _fishing_phase=="bite":
        var bite_phase:=_fishing_elapsed*15.0
        bobber_position+=Vector3(sin(bite_phase)*.42,-.12-absf(sin(bite_phase*.72))*.24,cos(bite_phase*1.27)*.36)
    else:
        bobber_position.y+=sin(_fishing_elapsed*3.2)*.035
    _fishing_bobber.global_position=bobber_position
    if is_instance_valid(_fishing_ripple):
        _fishing_ripple.global_position=Vector3(bobber_position.x,_fishing_target.y+.018,bobber_position.z)
        var ripple_scale:=1.0+fposmod(_fishing_elapsed*1.2,1.0)*.8
        _fishing_ripple.scale=Vector3.ONE*ripple_scale
    if is_instance_valid(_fishing_fish_shadow) and _fishing_fish_shadow.visible:
        _fishing_fish_shadow.global_position=Vector3(bobber_position.x,_fishing_target.y-.32,bobber_position.z)+Vector3(sin(_fishing_elapsed*10.0)*.44,0,cos(_fishing_elapsed*7.0)*.32)
        _fishing_fish_shadow.rotation.y=_fishing_elapsed*4.4
    _update_fishing_line(bobber_position)


func _update_fishing_line(bobber_position:Vector3)->void:
    if not is_instance_valid(_fishing_line):return
    var line_mesh:=ImmediateMesh.new()
    line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    var line_origin:Vector3=player.get_fishing_line_origin() if player.has_method("get_fishing_line_origin") else player.global_position+Vector3.UP*1.35+_combat_forward()*.45
    # ImmediateMesh vertices are local to FishingCastVisual, while both input
    # points are world coordinates.  Explicit conversion keeps the line seated
    # on the rod even if the director or visual root is transformed.
    line_mesh.surface_add_vertex(_fishing_visual.to_local(line_origin))
    line_mesh.surface_add_vertex(_fishing_visual.to_local(bobber_position+Vector3.UP*.42))
    line_mesh.surface_end()
    _fishing_line.mesh=line_mesh
func _notify(message:String,color:Color=Color.WHITE)->void:
    notification_requested.emit(message,color)


func _stream_local_gameplay(force_immediate:bool=false)->void:
    if not _stream_scene_branches:
        _stream_transition_queue.clear()
        return
    # Gameplay props, vendors, enemies, pickups and inactive dungeons are true
    # local chunks now. Hidden branches also stop their AnimationPlayers and
    # lights instead of merely relying on camera frustum culling.
    # Service visuals and interactables already have much shorter useful
    # ranges. Keeping a 430 m active bubble woke several neighbouring town
    # clusters at once; 320 m preserves approach visibility while unloading
    # their lights, animation players and props sooner.
    var load_radius:=185.0 if player.has_method("is_interior_mode") and player.is_interior_mode() else 320.0
    var radius_squared:=load_radius*load_radius
    for child in get_children():
        if not child is Node3D:continue
        var node:=child as Node3D
        if node.has_meta("always_streamed"):continue
        var loaded:=node.global_position.distance_squared_to(player.global_position)<=radius_squared
        if node.has_meta("stream_target") and bool(node.get_meta("stream_target"))==loaded:continue
        node.set_meta("stream_target",loaded)
        if force_immediate:
            _set_stream_loaded(node,loaded)
        elif bool(node.get_meta("stream_loaded",node.visible))==loaded:
            node.set_meta("stream_loaded",loaded)
        else:
            _stream_transition_queue.append({"node":node,"loaded":loaded})
    _refresh_local_prop_collisions()


func prepare_after_surface_teleport()->void:
    # The map keeps the scene paused during this call. Rebuild only the small
    # nearby collision pool now instead of making the first unpaused movement
    # frame discover and replace the entire previous area's set.
    _stream_tick=0.0
    _refresh_local_prop_collisions(true)
    _stream_transition_queue.clear()
    # Build the transition queue under the map. Main briefly advances it with
    # player input disabled before returning control; forcing every branch in
    # one call produced a larger single-frame render spike.
    _stream_local_gameplay(false)


func _apply_stream_transitions(max_transitions:int)->void:
    var applied:=0
    var inspected:=0
    while applied<max_transitions and inspected<8 and not _stream_transition_queue.is_empty():
        inspected+=1
        var transition:Dictionary=_stream_transition_queue.pop_back()
        var node:Node3D=transition.get("node") as Node3D
        if not is_instance_valid(node):continue
        var loaded:=bool(transition.get("loaded",true))
        if bool(node.get_meta("stream_target",not loaded))!=loaded:continue
        if bool(node.get_meta("stream_loaded",node.visible))==loaded:continue
        var started_usec:=Time.get_ticks_usec()
        _set_stream_loaded(node,loaded)
        _stream_transition_sequence+=1
        _last_stream_transition={
            "sequence":_stream_transition_sequence,
            "node":str(node.name),
            "loaded":loaded,
            "children":node.get_child_count(),
            "apply_ms":float(Time.get_ticks_usec()-started_usec)/1000.0,
            "queue_remaining":_stream_transition_queue.size(),
            "at_msec":Time.get_ticks_msec(),
        }
        applied+=1


func _set_stream_loaded(node:Node3D,loaded:bool)->void:
    node.set_meta("stream_loaded",loaded)
    if not _stream_scene_branches:
        return
    node.visible=true if node.get_meta("stream_keep_visible",false) else loaded
    node.process_mode=Node.PROCESS_MODE_INHERIT if loaded else Node.PROCESS_MODE_DISABLED


func _configure_resident_stream_visuals(root:Node3D)->void:
    for visual_value in root.find_children("*","GeometryInstance3D",true,false):
        var visual:=visual_value as GeometryInstance3D
        if not is_instance_valid(visual):continue
        visual.visibility_range_end=390.0
        visual.visibility_range_end_margin=45.0
        visual.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    for light_value in root.find_children("*","OmniLight3D",true,false):
        var light:=light_value as OmniLight3D
        if not is_instance_valid(light):continue
        light.distance_fade_enabled=true
        light.distance_fade_begin=300.0
        light.distance_fade_length=50.0
        light.distance_fade_shadow=260.0


func get_stream_diagnostics()->Dictionary:
    var now_msec:=Time.get_ticks_msec()
    var stream_age:=-1
    if not _last_stream_transition.is_empty():stream_age=now_msec-int(_last_stream_transition.get("at_msec",now_msec))
    var collision_age:=-1
    if not _last_collision_refresh.is_empty():collision_age=now_msec-int(_last_collision_refresh.get("at_msec",now_msec))
    return {
        "queue":_stream_transition_queue.size(),
        "last":_last_stream_transition.duplicate(),
        "stream_age_ms":stream_age,
        "collision":_last_collision_refresh.duplicate(),
        "collision_age_ms":collision_age,
    }

func camp_rest() -> void:
    player.hp=minf(player.max_hp,player.hp+maxf(16.0,player.max_hp*.18))
    player.mana=minf(player.max_mana,player.mana+maxf(10.0,player.max_mana*.22))


func _on_world_item_requested(action:String,item_id:String)->void:
    if action=="world_place_campfire":_place_player_campfire(item_id)


func _place_player_campfire(item_id:String)->void:
    _player_campfires=_player_campfires.filter(func(camp:Node3D)->bool:return is_instance_valid(camp))
    if _player_campfires.size()>=3:
        _notify("Only three travel campfires may remain active in this region",Color(1.0,.68,.28));return
    if player.has_method("is_interior_mode") and player.is_interior_mode():
        _notify("Build campfires outdoors on open ground",Color(1.0,.68,.28));return
    if player.has_method("is_mounted") and player.is_mounted():
        _notify("Dismount before building a camp",Color(1.0,.68,.28));return
    var forward:Vector3=player.get_combat_forward() if player.has_method("get_combat_forward") else Vector3.FORWARD
    var target:=player.global_position+Vector3(forward.x,0.0,forward.z).normalized()*3.6
    if walkable_sampler.is_valid() and not bool(walkable_sampler.call(target.x,target.z)):
        _notify("That ground is not safe for a campfire",Color(1.0,.68,.28));return
    var ground:=_ground(target)
    var maximum_delta:=0.0
    for offset in [Vector2(-1.2,0),Vector2(1.2,0),Vector2(0,-1.2),Vector2(0,1.2)]:
        maximum_delta=maxf(maximum_delta,absf(_ground(Vector3(target.x+offset.x,0,target.z+offset.y)).y-ground.y))
    if maximum_delta>.65:
        _notify("Find flatter ground before building the campfire",Color(1.0,.68,.28));return
    if not player.consume_bag_item(item_id,1):return
    var camp:=Node3D.new();camp.name="Player Travel Campfire";add_child(camp);camp.global_position=ground
    var timber:=Color(.29,.15,.055);var stone_color:=Color(.31,.30,.27)
    for yaw in [-.70,.70]:
        var log_mesh:=_service_box(camp,Vector3(0,.18,0),Vector3(2.0,.26,.30),timber);log_mesh.rotation.y=yaw
    for i in range(9):
        var angle:=TAU*float(i)/9.0
        _service_rock(camp,Vector3(cos(angle)*1.05,.18,sin(angle)*1.05),Vector3(.42,.34,.48),stone_color.lightened(float(i%3)*.035))
    var flame_material:=_service_material(Color(1.0,.22,.025)).duplicate() as StandardMaterial3D
    flame_material.emission_enabled=true;flame_material.emission=Color(1.0,.12,.01);flame_material.emission_energy_multiplier=3.2
    var flame:=MeshInstance3D.new();var flame_mesh:=SphereMesh.new();flame_mesh.radius=.32;flame_mesh.height=.95;flame_mesh.radial_segments=10;flame_mesh.rings=6;flame.mesh=flame_mesh;flame.position=Vector3(0,.64,0);flame.material_override=flame_material;camp.add_child(flame)
    var light:=OmniLight3D.new();light.position=Vector3(0,1.25,0);light.light_color=Color(1.0,.43,.16);light.light_energy=1.35;light.omni_range=10.0;light.shadow_enabled=false;camp.add_child(light)
    var marker:=Label3D.new();marker.text="TRAVEL CAMP\nE — COOK & REST";marker.position=Vector3(0,2.15,0);marker.font_size=22;marker.pixel_size=.009;marker.modulate=Color(1.0,.76,.33);marker.outline_size=6;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;camp.add_child(marker)
    _player_campfires.append(camp)
    _interactables.append({"action":"campfire","position":camp.global_position,"radius":3.4,"label":"Cook and rest","node":camp,"active":true,"station":{"name":"Travel Campfire","kind":"cooking"}})
    _notify("Campfire built — press E beside it to cook or rest",Color(1.0,.76,.34))

func _damage_player(amount:float)->void:
    if _admin_god_mode:return
    if player.has_method("has_equipment_effect") and player.has_equipment_effect("frostward"):amount*=.90
    player.hp=maxf(0.0,player.hp-maxf(0.0,amount))
    if amount>0.0 and player.has_method("damage_equipment"):
        var armor_slots:Array[String]=["head","chest","shoulders","hands","feet","pants"]
        player.damage_equipment(armor_slots[rng.randi_range(0,armor_slots.size()-1)],.18+amount*.018)

func apply_environment_damage(amount:float,source:String="environment")->void:
    if _admin_god_mode:return
    var before:float=player.hp
    _damage_player(amount)
    var applied:=maxf(0.0,before-player.hp)
    if applied<=0.0:return
    if player.hp<=0.0 or source=="fatal_fall":
        notification_requested.emit("The fall was fatal.",Color(0.95,0.25,0.18))
    else:
        notification_requested.emit("Fall damage  -%d"%roundi(applied),Color(1.0,0.58,0.20))

func get_admin_status() -> Dictionary:
    return {"class":player.active_class,"enemies":minions.size(),"loot":loot.size(),"gold":player.hero_gold,"level":player.hero_level,"skills":skill_levels,"herbs":player.herbs,"scrap":player.scrap,"ore":player.ore,"essence":player.essence,"one_hit_kill":_admin_one_hit_kill,"god_mode":_admin_god_mode}

func teleport_to_town(index:int)->void:
    var towns:Array=profile.get("town_sites",[])
    if index>=0 and index<towns.size():
        var p:Vector2=towns[index].get("position",Vector2.ZERO)
        var destination:=_ground(Vector3(p.x,0,p.y))
        if player.has_method("teleport_to_surface"):player.teleport_to_surface(destination)
        else:player.set_interior_mode(false);player.global_position=destination
        prepare_after_surface_teleport()

func teleport_to_nearest_bridge()->void:
    var bridge_sites:Array=profile.get("ford_sites",[])
    if bridge_sites.is_empty() or not is_instance_valid(player):
        return
    var player_point:=Vector2(player.global_position.x,player.global_position.z)
    var nearest_point:Vector2=bridge_sites[0].get("position",Vector2.ZERO)
    var nearest_distance:=player_point.distance_squared_to(nearest_point)
    for site in bridge_sites:
        var bridge_point:Vector2=site.get("position",Vector2.ZERO)
        var distance:=player_point.distance_squared_to(bridge_point)
        if distance<nearest_distance:
            nearest_distance=distance
            nearest_point=bridge_point
    var road_direction:=_road_direction_at(nearest_point)
    var approach_a:=nearest_point+road_direction*70.0
    var approach_b:=nearest_point-road_direction*70.0
    var destination:=approach_a if player_point.distance_squared_to(approach_a)<player_point.distance_squared_to(approach_b) else approach_b
    var ground_destination:=_ground(Vector3(destination.x,0.0,destination.y))
    if player.has_method("teleport_to_surface"):player.teleport_to_surface(ground_destination)
    else:player.set_interior_mode(false);player.global_position=ground_destination
    prepare_after_surface_teleport()

func _road_direction_at(point:Vector2)->Vector2:
    var best_direction:=Vector2(0.0,1.0)
    var best_distance:=INF
    for road in profile.get("road_corridors",[]):
        var points:Array=road.get("points",[])
        for i in range(points.size()-1):
            var a:Vector2=points[i]
            var b:Vector2=points[i+1]
            var segment:=b-a
            var length_squared:=segment.length_squared()
            if length_squared<=0.0001:
                continue
            var t:=clampf((point-a).dot(segment)/length_squared,0.0,1.0)
            var distance:=point.distance_squared_to(a+segment*t)
            if distance<best_distance:
                best_distance=distance
                best_direction=segment.normalized()
    return best_direction

func _build_town_services()->void:
    var town_index:=0
    for site in _town_service_sites():
        var p:Vector2=site.get("position",Vector2.ZERO)
        var types:Array[String]=["provisioner","armorer"]
        var architecture_set:=str(site.get("architecture_set",""))
        if architecture_set=="icewatch_hold":types=["glacial_outfitter","armorer","provisioner"]
        elif architecture_set=="rimegate_lodge":types=["rime_smith","alchemist"]
        elif architecture_set=="rainward_timber":
            if str(site.get("name",""))=="Rainhaven":types.assign(["river_trader","alchemist"])
            else:types.assign(["woodwright","provisioner"])
        elif architecture_set=="rainward_stone":types=["quarry_mason","armorer"]
        elif architecture_set=="stormbreak_highland":
            var highland_town:=str(site.get("name",""))
            if highland_town=="Stormbreak Hold":types.assign(["storm_warden","highland_smith","provisioner"])
            elif highland_town=="Moorwatch":types.assign(["peatwright","alchemist"])
            else:types.assign(["drover","armorer"])
        elif architecture_set=="skeld_coast":
            var skeld_town:=str(site.get("name",""))
            if skeld_town=="Frostharbor":types=["skeld_harbormaster","skeld_netwright","provisioner"]
            elif skeld_town=="Vardholm":types=["rime_warden","skeld_smith","provisioner"]
            else:types=["skeld_netwright","alchemist"]
        elif architecture_set=="marcher_stone":
            var marcher_stone_town:=str(site.get("name",""))
            if marcher_stone_town=="March Keep":types=["march_warden","ember_smith","provisioner"]
            else:types=["march_factor","provisioner"]
        elif architecture_set=="marcher_timber":
            if str(site.get("name",""))=="Amberfield":types=["grain_factor","alchemist"]
            else:types=["saltmonger","armorer"]
        elif site.get("capital",false):types=["alchemist","armorer","provisioner","arcanist"]
        elif town_index%2==0:types=["provisioner","alchemist"]
        for i in range(types.size()):
            var angle:=float(i)*TAU/maxf(1.0,types.size())+.35
            var distance:=24.0 if site.get("capital",false) else 17.0
            var vendor_pos:=p+Vector2(cos(angle),sin(angle))*distance
            var vendor_data:=_vendor_catalog(types[i],str(site.get("name","Town")))
            var vendor:=Node3D.new();vendor.name="%s_%s"%[site.get("name","Town"),types[i].capitalize()];vendor.set_meta("vendor_data",vendor_data);add_child(vendor);vendor.global_position=_ground(Vector3(vendor_pos.x,0,vendor_pos.y));_vendors.append(vendor)
            var apron_color:Color=vendor_data.get("color",Color(.6,.3,.1))
            _add_service_person(vendor,apron_color,true)
            _add_vendor_counter(vendor,types[i],apron_color)
            vendor.rotation.y=angle+PI
            var sign:=Label3D.new();sign.text="%s\nE — BROWSE"%vendor_data.get("type_name","MERCHANT").to_upper();sign.position=Vector3(0,2.45,0);sign.font_size=34;sign.modulate=Color(1,.84,.42);sign.outline_size=8;sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED;vendor.add_child(sign)
            # Merchant roots contain enough separate meshes that hiding the
            # whole branch can stall the renderer a few frames later. Keep the
            # resources resident and let native distance culling retire each
            # visual without rebuilding the render branch.
            vendor.set_meta("stream_keep_visible",true)
            vendor.set_meta("always_streamed",true)
            _configure_resident_stream_visuals(vendor)
        # A small scheduled population makes settlements feel inhabited. Only
        # nearby citizens think or animate; distant towns cost a visibility
        # check at 10 Hz and nothing more.
        _add_townfolk(site,10 if site.get("capital",false) else 4)
        town_index+=1
    for p in [Vector2(-2700,1700),Vector2(2620,-1800)]:
        var cave:=Node3D.new();cave.name="MountainsideCaveEntranceWest" if p.x<0 else "MountainsideCaveEntranceEast";add_child(cave);cave.global_position=_ground(Vector3(p.x,0,p.y))
        if p.x < 0: cave.rotation.y=PI
        _build_recessed_cave(cave)


func _town_service_sites()->Array:
    var sites:Array=[]
    var spawn_site:Dictionary=profile.get("spawn_site",{})
    if not spawn_site.is_empty() and not spawn_site.get("starter",false):
        sites.append(spawn_site)
    for site in profile.get("town_sites",[]):sites.append(site)
    return sites


func _build_recessed_cave(cave:Node3D)->void:
    # The old boolean-cut sphere read as a separate faceted boulder and exposed
    # bright CSG interior faces. The terrain already forms the mountain mass;
    # this clean, textured rock face is embedded into that mass and contains a
    # real arch-shaped opening with opaque darkness directly behind it.
    _add_cave_rock_face(cave)
    # The stable terrain corridor now carries the approach. Keep the separate
    # cave floor behind the black mouth so it cannot read as a dark runway laid
    # across the grass.
    _service_solid_box(cave,Vector3(0,.08,-27.0),Vector3(17.2,.16,22.0),Color(.072,.066,.055))
    _add_cave_mouth_darkness(cave,-15.72)
    _add_dungeon_torch(cave,Vector3(-7.2,3.1,-15.25),1.0)
    _add_dungeon_torch(cave,Vector3(7.2,3.1,-15.25),-1.0)


func _add_cave_rock_face(cave:Node3D)->void:
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var z:=-15.86
    _cave_face_quad(st,Vector3(-36.0,.05,z),Vector3(-8.6,.05,z),Vector3(-8.6,18.0,z),Vector3(-27.0,11.2,z))
    _cave_face_quad(st,Vector3(8.6,.05,z),Vector3(36.0,.05,z),Vector3(27.0,11.2,z),Vector3(8.6,18.0,z))
    for i in range(16):
        var a0:=PI*float(i)/16.0
        var a1:=PI*float(i+1)/16.0
        var inner0:=Vector3(cos(a0)*8.6,5.2+sin(a0)*8.6,z)
        var inner1:=Vector3(cos(a1)*8.6,5.2+sin(a1)*8.6,z)
        var outer0:=Vector3(inner0.x,19.0-absf(inner0.x)*.12,z)
        var outer1:=Vector3(inner1.x,19.0-absf(inner1.x)*.12,z)
        _cave_face_quad(st,inner1,inner0,outer0,outer1)
    st.generate_normals()
    var face:=MeshInstance3D.new();face.name="EmbeddedCaveRockFace";face.mesh=st.commit()
    var material:=StandardMaterial3D.new();material.albedo_color=Color(.62,.61,.55);material.roughness=1.0;material.albedo_texture=load("res://assets/terrain/highland_stone_v1.png");material.uv1_scale=Vector3(.12,.12,.12);material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;material.cull_mode=BaseMaterial3D.CULL_DISABLED
    face.material_override=material;cave.add_child(face);face.create_trimesh_collision()


func _cave_face_quad(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,d:Vector3)->void:
    for vertex in [a,b,c,a,c,d]:
        st.set_uv(Vector2(vertex.x*.10,-vertex.y*.10));st.add_vertex(vertex)


func _add_cave_mouth_darkness(cave:Node3D,z_position:float)->void:
    # A flat, non-colliding arch at the front makes the entrance readable from
    # a distance. It is deliberately a visual portal rather than another wall:
    # the hero walks straight through it into the generous travel trigger.
    var outline:=PackedVector2Array([Vector2(-8.6,.12),Vector2(8.6,.12),Vector2(8.6,5.2)])
    for i in range(1,17):
        var angle:=PI*float(i)/16.0
        outline.append(Vector2(cos(angle)*8.6,5.2+sin(angle)*8.6))
    var triangles:=Geometry2D.triangulate_polygon(outline)
    var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index in triangles:
        var point:=outline[index]
        st.set_normal(Vector3(0,0,1));st.add_vertex(Vector3(point.x,point.y,z_position))
    var darkness:=MeshInstance3D.new();darkness.name="VisibleBlackCaveMouth";darkness.mesh=st.commit();darkness.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material:=StandardMaterial3D.new();material.albedo_color=Color(.002,.003,.004);material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.cull_mode=BaseMaterial3D.CULL_DISABLED
    darkness.material_override=material;cave.add_child(darkness)


func _build_dungeon_network()->void:
    _portals.clear()
    var spawn2:Vector2=profile.get("spawn_site",{}).get("position",Vector2.ZERO)
    var well2:=spawn2+Vector2(-34.0,30.0)
    var well_ground:=_ground(Vector3(well2.x,0,well2.y))
    _build_surface_dungeon_well(well_ground)

    var well_base:=Vector3(8000.0,-82.0,0.0)
    var west_base:=Vector3(8200.0,-96.0,0.0)
    var east_base:=Vector3(8420.0,-112.0,0.0)
    _build_well_dungeon(well_base)
    _build_cavern_dungeon(west_base,3,"WEST CAVERN")
    _build_cavern_dungeon(east_base,4,"EAST CAVERN")

    var well_entry:=well_base+Vector3(0,.12,58.0)
    _register_portal(well_ground,well_entry,"Climb down the well",true,4.7)
    _register_portal(well_entry,well_ground+Vector3(0,.18,5.2),"Climb back to Riverwatch",false,4.0)

    # Use the carved tunnel floor elevation, not the lowered heightfield below
    # it; otherwise the 3D interaction radius can sit many units under the hero.
    var west_mouth:=_ground(Vector3(-2700.0,0,1700.0))
    var east_mouth:=_ground(Vector3(2620.0,0,-1800.0))
    # Place the travel volume just inside the visible mouth instead of against
    # the rear wall. A broad E zone covers the approach and walking several
    # steps into the opening enters automatically.
    var west_surface:=Vector3(-2700.0,west_mouth.y+.2,1712.0)
    var east_surface:=Vector3(2620.0,east_mouth.y+.2,-1812.0)
    var west_entry:=west_base+Vector3(0,.12,88.0)
    var east_entry:=east_base+Vector3(0,.12,88.0)
    _register_portal(west_surface,west_entry,"Enter the West Cavern - Rank III",true,22.0,true,true,12.5)
    _register_portal(east_surface,east_entry,"Enter the East Cavern - Rank IV",true,22.0,true,true,12.5)
    _register_portal(west_entry,_ground(Vector3(-2700.0,0,1692.0)),"Return to the mountainside",false,4.2)
    _register_portal(east_entry,_ground(Vector3(2620.0,0,-1792.0)),"Return to the mountainside",false,4.2)
    _add_portal_marker(Vector3(-2700.0,west_mouth.y+.2,1702.0),"WEST CAVERN - RANK III\nWALK INSIDE OR PRESS E")
    _add_portal_marker(Vector3(2620.0,east_mouth.y+.2,-1802.0),"EAST CAVERN - RANK IV\nWALK INSIDE OR PRESS E")


func _register_portal(position:Vector3,destination:Vector3,label:String,interior:bool,radius:float,horizontal:bool=false,auto_enter:bool=false,auto_radius:float=0.0)->void:
    _portals.append({"action":"travel","position":position,"destination":destination,"label":label,"interior":interior,"radius":radius,"horizontal":horizontal,"auto_enter":auto_enter,"auto_radius":auto_radius if auto_radius>0.0 else radius})


func _register_dungeon_chest(position:Vector3,label:String,rank:int,chest:Node3D,lid:Node3D,marker:Label3D,boss_gate:String="")->void:
    _portals.append({"action":"chest","position":position,"label":label,"rank":rank,"radius":4.2,"chest":chest,"lid":lid,"marker":marker,"looted":false,"boss_gate":boss_gate})


func _add_portal_marker(position:Vector3,text:String)->void:
    var marker:=Label3D.new();marker.text=text;marker.font_size=34;marker.pixel_size=.012;marker.modulate=Color(.84,.63,.27);marker.outline_size=8;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;add_child(marker);marker.global_position=position+Vector3.UP*2.5


func _build_surface_dungeon_well(ground:Vector3)->void:
    var well:=Node3D.new();well.name="RiverwatchDungeonWell";add_child(well);well.global_position=ground
    for i in range(14):
        var angle:=float(i)*TAU/14.0
        var stone:=_service_solid_box(well,Vector3(cos(angle)*2.65,.62,sin(angle)*2.65),Vector3(1.42,1.24,1.05),Color(.42,.43,.40))
        stone.rotation.y=-angle
    var opening:=MeshInstance3D.new();var opening_mesh:=CylinderMesh.new();opening_mesh.top_radius=2.15;opening_mesh.bottom_radius=2.15;opening_mesh.height=.08;opening.mesh=opening_mesh;opening.position=Vector3(0,.03,0);opening.material_override=_service_material(Color(.008,.009,.012));well.add_child(opening)
    for x in [-3.2,3.2]:_service_solid_box(well,Vector3(x,2.45,0),Vector3(.34,4.9,.34),Color(.27,.16,.075))
    _service_solid_box(well,Vector3(0,4.72,0),Vector3(7.0,.34,.34),Color(.27,.16,.075))
    _service_box(well,Vector3(0,3.2,0),Vector3(.10,3.0,.10),Color(.16,.10,.05))
    var sign:=Label3D.new();sign.text="RIVERWATCH WELL\nE - DESCEND";sign.position=Vector3(0,5.5,0);sign.font_size=32;sign.pixel_size=.011;sign.modulate=Color(.93,.78,.43);sign.outline_size=7;sign.billboard=BaseMaterial3D.BILLBOARD_ENABLED;well.add_child(sign)


func _build_well_dungeon(base:Vector3)->void:
    var dungeon:=Node3D.new();dungeon.name="RiverwatchWellDungeon";dungeon.position=base;add_child(dungeon)
    _build_dungeon_shell(dungeon,84.0,132.0,Color(.31,.30,.27),Color(.21,.20,.18),7.5)
    var wall:=Color(.255,.245,.22)
    # A cell-authored maze leaves only the intentional route open. This turns
    # the old warehouse of partition walls into real corridors, corners,
    # branch rooms, a dead end and a secret spur while keeping navigation
    # deterministic for both the player and collision-tested enemies.
    var walkable:Dictionary={}
    var route_cells:=[
        Vector2i(4,12),Vector2i(4,11),Vector2i(4,10),
        Vector2i(3,10),Vector2i(2,10),Vector2i(1,10),
        Vector2i(1,9),Vector2i(1,8),Vector2i(1,7),
        Vector2i(2,7),Vector2i(3,7),Vector2i(4,7),Vector2i(5,7),Vector2i(6,7),Vector2i(7,7),
        Vector2i(7,6),Vector2i(7,5),Vector2i(7,4),
        Vector2i(6,4),Vector2i(5,4),Vector2i(4,4),Vector2i(3,4),
        Vector2i(3,3),Vector2i(3,2),Vector2i(3,1),
        Vector2i(4,1),Vector2i(5,1),Vector2i(3,0),Vector2i(4,0),Vector2i(5,0),
        # Key branch, false lead, reading alcove and hidden smuggler spur.
        Vector2i(0,8),Vector2i(4,8),Vector2i(5,8),Vector2i(8,5),
        Vector2i(2,4),Vector2i(1,4)
    ]
    for cell in route_cells:walkable[cell]=true
    # Build the maze from thin dressed corridor walls instead of filling every
    # unused cell with a cube. The route now reads as architecture rather than
    # a pile of blocks, while preserving exactly the same navigation graph.
    var directions:Array[Vector2i]=[Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]
    for cell_value in walkable:
        var cell:Vector2i=cell_value
        var center:=Vector3(-36.0+float(cell.x)*9.0,2.6,-54.0+float(cell.y)*9.0)
        for direction:Vector2i in directions:
            var neighbor:Vector2i=cell+direction
            if walkable.has(neighbor):continue
            if cell==Vector2i(4,12) and direction==Vector2i(0,1):continue
            var wall_position:=center+Vector3(float(direction.x)*4.5,0,float(direction.y)*4.5)
            var wall_size:=Vector3(.78,5.2,9.15) if direction.x!=0 else Vector3(9.15,5.2,.78)
            _add_well_dungeon_wall(dungeon,wall_position,wall_size,wall.darkened(.025+float((cell.x+cell.y)%2)*.025))
    _add_secret_dungeon_wall(dungeon,Vector3(-22.5,2.6,-18.0),Vector3(1.0,5.2,8.3),"SMUGGLER'S CACHE")
    _add_dungeon_chest(dungeon,Vector3(-27.0,0,-18.0),2,"Hidden Smuggler Cache")
    for light_position in [Vector3(0,5.9,54),Vector3(-27,5.9,36),Vector3(-27,5.9,9),Vector3(0,5.9,9),Vector3(27,5.9,9),Vector3(27,5.9,-18),Vector3(-9,5.9,-18),Vector3(-9,5.9,-45),Vector3(0,5.9,-54)]:
        _add_dungeon_ceiling_light(dungeon,light_position)
    # Every torch is mounted against an actual corridor wall; none floats in
    # the centre of a hall.
    for torch_data in [
        [Vector3(4.12,2.8,50),-1.0],[Vector3(-18,2.8,31.88),1.0],
        [Vector3(-20,2.8,13.12),-1.0],[Vector3(31.88,2.8,-5),-1.0],
        [Vector3(9,2.8,-13.88),1.0],[Vector3(-13.12,2.8,-36),1.0],
    ]:
        _add_dungeon_torch(dungeon,torch_data[0],torch_data[1])
    _add_dungeon_ladder(dungeon,Vector3(0,0,61.0))
    _add_dungeon_key(dungeon,Vector3(-36.0,.6,18.0),"well_cellar_key","Cellar Key")
    _add_locked_dungeon_gate(dungeon,Vector3(-9.0,2.6,-40.5),8.6,"well_cellar_key","Cellar Key")
    _add_dungeon_chest(dungeon,Vector3(0,0,-54.0),2,"Riverwatch Well Hoard")
    var bounds:=Rect2(Vector2(base.x-40.0,base.z-64.0),Vector2(80.0,128.0))
    var imp_positions:=[Vector3(0,.12,45),Vector3(-27,.12,27),Vector3(-9,.12,9),Vector3(27,.12,0),Vector3(9,.12,-18),Vector3(-9,.12,-36),Vector3(9,.12,-54)]
    for i in range(imp_positions.size()):_spawn_minion(0,float(i),base+imp_positions[i],1,bounds)


func _add_well_dungeon_wall(root:Node3D,position:Vector3,size:Vector3,color:Color)->void:
    _service_solid_box(root,position,size,color)
    var horizontal:=size.x>size.z
    var trim_size:=Vector3(size.x,.28,.98) if horizontal else Vector3(.98,.28,size.z)
    _service_box(root,Vector3(position.x,.32,position.z),trim_size,Color(.14,.13,.115))
    _service_box(root,Vector3(position.x,5.04,position.z),trim_size,Color(.34,.31,.26))
    # Shallow inset panels break long silhouettes without protruding into the
    # walkable corridor.
    var panel_size:=Vector3(minf(5.8,size.x*.72),2.55,.84) if horizontal else Vector3(.84,2.55,minf(5.8,size.z*.72))
    _service_box(root,Vector3(position.x,2.55,position.z),panel_size,color.lightened(.055))


func _build_cavern_dungeon(base:Vector3,rank:int,title:String)->void:
    var dungeon:=Node3D.new();dungeon.name=title.capitalize().replace(" ","");dungeon.position=base;add_child(dungeon)
    _build_dungeon_shell(dungeon,128.0,190.0,Color(.235,.225,.205),Color(.17,.165,.15),14.0)
    # A broad, torch-lit stone route opens through two imp halls into a separate
    # cathedral-sized dragon chamber at the back of the cavern.
    for z in [52.0,14.0,-28.0]:
        _service_solid_box(dungeon,Vector3(-35.5,4.0,z),Vector3(57.0,8.0,2.0),Color(.22,.21,.19))
        _service_solid_box(dungeon,Vector3(35.5,4.0,z),Vector3(57.0,8.0,2.0),Color(.22,.21,.19))
    # Alternating side passages form an actual crawl through guard rooms and
    # alcoves instead of one uninterrupted warehouse-sized chamber.
    _service_solid_box(dungeon,Vector3(-27.0,4.0,33.0),Vector3(2.0,8.0,28.0),Color(.225,.215,.195))
    _service_solid_box(dungeon,Vector3(27.0,4.0,-4.0),Vector3(2.0,8.0,28.0),Color(.225,.215,.195))
    _service_solid_box(dungeon,Vector3(-27.0,4.0,-37.0),Vector3(2.0,8.0,14.0),Color(.225,.215,.195))
    _service_solid_box(dungeon,Vector3(-27.0,4.0,-56.0),Vector3(2.0,8.0,8.0),Color(.225,.215,.195))
    for x in [-50.0,-25.0,25.0,50.0]:
        for z in [72.0,34.0,-4.0,-50.0,-82.0]:_service_solid_box(dungeon,Vector3(x,3.2,z),Vector3(3.0,6.4,3.0),Color(.20,.19,.17))
    # Raised final dais and royal-blue carpet identify the boss/reward room.
    _service_solid_box(dungeon,Vector3(0,.38,-72.0),Vector3(52.0,.76,38.0),Color(.24,.215,.17))
    _service_box(dungeon,Vector3(0,.79,-70.0),Vector3(10.0,.035,40.0),Color(.025,.075,.22))
    for z in [78.0,56.0,30.0,8.0,-18.0,-46.0,-78.0]:
        _add_dungeon_torch(dungeon,Vector3(-61.0,3.2,z),1.0)
        _add_dungeon_torch(dungeon,Vector3(61.0,3.2,z),-1.0)
    for z in [-50.0,-80.0]:
        _add_dungeon_torch(dungeon,Vector3(-24.0,3.0,z),1.0)
        _add_dungeon_torch(dungeon,Vector3(24.0,3.0,z),-1.0)
    for z in [78.0,58.0,34.0,8.0,-18.0,-46.0,-74.0]:
        _add_dungeon_ceiling_light(dungeon,Vector3(0,10.8,z))
        _service_box(dungeon,Vector3(0,.035,z),Vector3(5.0,.035,8.0),Color(.18,.075,.045) if z>-20.0 else Color(.035,.12,.26))
    var title_marker:=Label3D.new();title_marker.text="%s\nIMP HALLS - DRAGON SANCTUM"%title;title_marker.position=Vector3(0,3.4,84.0);title_marker.font_size=34;title_marker.pixel_size=.012;title_marker.modulate=Color(.86,.46,.20);title_marker.outline_size=8;dungeon.add_child(title_marker)
    var prefix:=title.to_lower().replace(" ","_")
    _add_dungeon_key(dungeon,Vector3(48.0,.7,70.0),"%s_hall_key"%prefix,"Imp Hall Key")
    _add_locked_dungeon_gate(dungeon,Vector3(0,3.4,52.0),13.0,"%s_hall_key"%prefix,"Imp Hall Key")
    _add_secret_dungeon_wall(dungeon,Vector3(-27.0,4.0,-48.0),Vector3(2.0,8.0,8.0),"HIDDEN RELIQUARY")
    _add_dungeon_chest(dungeon,Vector3(-45.0,.2,-48.0),rank+1,"Hidden Cavern Reliquary")
    var boss_id:="%s_DRAGON"%title.replace(" ","_")
    _add_dungeon_chest(dungeon,Vector3(0,1.15,-84.0),rank+3,"Royal Dragon Hoard",boss_id)
    var bounds:=Rect2(Vector2(base.x-60.0,base.z-91.0),Vector2(120.0,182.0))
    for i in range(10):
        var p:=base+Vector3(-36.0+float(i%3)*36.0,.12,58.0-float(i/3)*22.0)
        _spawn_minion(0,float(i),p,rank,bounds)
    _spawn_dragon(base+Vector3(0,.82,-62.0),rank+3,bounds,boss_id)


func _build_dungeon_shell(root:Node3D,width:float,depth:float,floor_color:Color,wall_color:Color,height:float=7.0)->void:
    _service_solid_box(root,Vector3(0,-.3,0),Vector3(width,.6,depth),floor_color)
    _service_solid_box(root,Vector3(-width*.5,height*.5,0),Vector3(1.2,height,depth),wall_color)
    _service_solid_box(root,Vector3(width*.5,height*.5,0),Vector3(1.2,height,depth),wall_color)
    _service_solid_box(root,Vector3(0,height*.5,-depth*.5),Vector3(width,height,1.2),wall_color)
    _service_solid_box(root,Vector3(0,height*.5,depth*.5),Vector3(width,height,1.2),wall_color)
    _service_solid_box(root,Vector3(0,height+.25,0),Vector3(width,.5,depth),Color(wall_color.r*.72,wall_color.g*.72,wall_color.b*.72))


func _add_dungeon_ladder(root:Node3D,position:Vector3)->void:
    for x in [-1.15,1.15]:_service_box(root,position+Vector3(x,3.0,0),Vector3(.18,6.0,.18),Color(.32,.19,.08))
    for y in range(8):_service_box(root,position+Vector3(0,.45+float(y)*.72,0),Vector3(2.5,.14,.18),Color(.32,.19,.08))


func _add_dungeon_torch(root:Node3D,position:Vector3,side:float)->void:
    _service_box(root,position,Vector3(.22,1.0,.22),Color(.20,.12,.05))
    var flame:=MeshInstance3D.new();flame.name="DungeonTorchFlame";var flame_mesh:=SphereMesh.new();flame_mesh.radius=.20;flame_mesh.height=.58;flame_mesh.radial_segments=7;flame_mesh.rings=4;flame.mesh=flame_mesh;flame.position=position+Vector3(side*.25,.7,0);var flame_mat:=_service_material(Color(1.0,.25,.035));flame_mat.emission_enabled=true;flame_mat.emission=Color(1.0,.12,.02);flame_mat.emission_energy_multiplier=2.8;flame.material_override=flame_mat;root.add_child(flame)
    var light:=OmniLight3D.new();light.name="DungeonTorchLight";light.position=position+Vector3(side*.5,.85,0);light.light_color=Color(1.0,.55,.26);light.light_energy=2.25;light.omni_range=18.0;light.shadow_enabled=false;root.add_child(light)


func _add_dungeon_ceiling_light(root:Node3D,position:Vector3)->void:
    var lantern:=Node3D.new();lantern.name="DungeonGuideLantern";lantern.position=position;root.add_child(lantern)
    _service_box(lantern,Vector3.ZERO,Vector3(.75,.18,.75),Color(.58,.39,.12))
    var glow:=OmniLight3D.new();glow.name="DungeonGuideLight";glow.light_color=Color(1.0,.69,.42);glow.light_energy=2.0;glow.omni_range=25.0;glow.shadow_enabled=false;lantern.add_child(glow)


func _add_dungeon_chest(root:Node3D,position:Vector3,rank:int,title:String,boss_gate:String="")->void:
    var chest:=Node3D.new();chest.name=title.replace(" ","");chest.position=position;root.add_child(chest)
    var royal:=not boss_gate.is_empty()
    _service_solid_box(chest,Vector3(0,.52,0),Vector3(4.2,1.04,2.55),Color(.025,.075,.22) if royal else Color(.30,.145,.055))
    var lid:=_service_solid_box(chest,Vector3(0,1.30,-.04),Vector3(4.2,.58,2.55),Color(.045,.12,.34) if royal else Color(.39,.19,.065))
    for x in [-1.55,0.0,1.55]:_service_box(chest,Vector3(x,.92,-1.29),Vector3(.20,1.65,.09),Color(.76,.48,.08))
    var lock_plate:=_service_solid_box(chest,Vector3(0,.93,-1.36),Vector3(.62,.72,.18),Color(.82,.56,.10))
    lock_plate.collision_layer=0
    var marker:=Label3D.new();marker.text="E - OPEN\n%s"%title.to_upper();marker.position=Vector3(0,2.45,0);marker.font_size=30;marker.pixel_size=.010;marker.modulate=Color(1.0,.76,.25);marker.outline_size=7;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;chest.add_child(marker)
    _register_dungeon_chest(root.to_global(position),"Open %s"%title,rank,chest,lid,marker,boss_gate)


func _add_dungeon_key(root:Node3D,position:Vector3,key_id:String,item_name:String)->void:
    var pedestal:=Node3D.new();pedestal.name=item_name.replace(" ","");pedestal.position=position;root.add_child(pedestal)
    var plinth:=CylinderMesh.new();plinth.top_radius=.62;plinth.bottom_radius=.78;plinth.height=.58;plinth.radial_segments=12
    var plinth_mesh:=MeshInstance3D.new();plinth_mesh.mesh=plinth;plinth_mesh.position.y=.29;plinth_mesh.material_override=_service_material(Color(.22,.20,.16));pedestal.add_child(plinth_mesh)
    var gold:=_service_material(Color(.94,.64,.12))
    var key_root:=Node3D.new();key_root.name="VisibleDungeonKey";key_root.position=Vector3(0,1.28,0);key_root.rotation.z=PI*.5;pedestal.add_child(key_root)
    var shaft:=CylinderMesh.new();shaft.top_radius=.075;shaft.bottom_radius=.075;shaft.height=1.15;shaft.radial_segments=10
    var shaft_mesh:=MeshInstance3D.new();shaft_mesh.mesh=shaft;shaft_mesh.material_override=gold;key_root.add_child(shaft_mesh)
    var ring_mesh:=TorusMesh.new();ring_mesh.inner_radius=.16;ring_mesh.outer_radius=.29;ring_mesh.rings=12;ring_mesh.ring_segments=8
    var ring:=MeshInstance3D.new();ring.mesh=ring_mesh;ring.position.y=.67;ring.material_override=gold;key_root.add_child(ring)
    _service_box(key_root,Vector3(.16,-.47,0),Vector3(.32,.10,.13),Color(.94,.64,.12))
    _service_box(key_root,Vector3(.25,-.30,0),Vector3(.18,.10,.13),Color(.94,.64,.12))
    var marker:=Label3D.new();marker.text="E — TAKE\n%s"%item_name.to_upper();marker.position=Vector3(0,2.15,0);marker.font_size=27;marker.pixel_size=.010;marker.modulate=Color(1,.74,.25);marker.outline_size=7;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;pedestal.add_child(marker)
    _portals.append({"action":"dungeon_key","position":root.to_global(position),"radius":3.4,"label":"Take %s"%item_name,"key_id":key_id,"item_name":item_name,"node":pedestal,"collected":false})


func _add_locked_dungeon_gate(root:Node3D,position:Vector3,width:float,key_id:String,item_name:String)->void:
    var gate:=StaticBody3D.new();gate.name="LockedPortcullis";gate.position=position;gate.collision_layer=1;root.add_child(gate)
    var collision:=CollisionShape3D.new();var collision_shape:=BoxShape3D.new();collision_shape.size=Vector3(width,6.2,.42);collision.shape=collision_shape;gate.add_child(collision)
    var iron:=Color(.28,.31,.32);var trim:=Color(.55,.36,.12)
    for x in range(-floori(width*.5)+1,ceili(width*.5),2):
        _service_box(gate,Vector3(float(x),0,0),Vector3(.24,5.9,.24),iron)
        _dragon_cone(gate,Vector3(float(x),-3.18,0),.19,.65,iron,Vector3(0,0,PI))
    _service_box(gate,Vector3(0,2.65,0),Vector3(width,.34,.34),trim)
    _service_box(gate,Vector3(0,-.65,0),Vector3(width,.24,.30),trim)
    var marker:=Label3D.new();marker.text="LOCKED GATE\nE — USE %s"%item_name.to_upper();marker.position=position+Vector3(0,1.2,-.55);marker.font_size=28;marker.pixel_size=.010;marker.modulate=Color(1,.55,.20);marker.outline_size=7;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;root.add_child(marker)
    _portals.append({"action":"dungeon_door","position":root.to_global(position),"radius":5.2,"label":"Unlock gate","key_id":key_id,"item_name":item_name,"door":gate,"marker":marker,"unlocked":false})


func _add_secret_dungeon_wall(root:Node3D,position:Vector3,size:Vector3,secret_name:String)->void:
    var wall:=_service_solid_box(root,position,size,Color(.245,.235,.215))
    wall.name="SecretWall_%s"%secret_name.replace(" ","_")
    var marker:=Label3D.new();marker.text="CRACKED STONE\nE - INSPECT";marker.position=position+Vector3(0,.35,-size.z*.52);marker.font_size=20;marker.pixel_size=.008;marker.modulate=Color(.62,.57,.48);marker.outline_size=5;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;marker.visibility_range_end=13.0;root.add_child(marker)
    _interactables.append({"action":"secret_wall","position":root.to_global(position),"radius":4.2,"label":"Inspect cracked stone","node":wall,"marker":marker,"active":true})

func _tick_townfolk(delta:float)->void:
    if not is_instance_valid(player):return
    var space:=get_world_3d().direct_space_state
    for index in range(_townfolk.size()-1,-1,-1):
        var citizen:Dictionary=_townfolk[index]
        var node:=citizen.get("node") as Node3D
        if not is_instance_valid(node):_townfolk.remove_at(index);continue
        var distance_squared:=node.global_position.distance_squared_to(player.global_position)
        if distance_squared>22500.0:
            node.visible=false
            continue
        node.visible=true
        citizen.pause=float(citizen.get("pause",0.0))-delta
        citizen.phase=float(citizen.get("phase",0.0))+delta
        var current:=Vector2(node.global_position.x,node.global_position.z)
        var target:Vector2=citizen.get("target",current)
        if current.distance_to(target)<1.2:
            if float(citizen.pause)<=0.0:
                var heading:=rng.randf_range(-PI,PI)
                var distance:=rng.randf_range(8.0,float(citizen.get("radius",36.0)))
                var center:Vector2=citizen.get("center",current)
                citizen.target=center+Vector2(cos(heading),sin(heading))*distance
                citizen.pause=rng.randf_range(1.2,5.0)
            _animate_townsperson(node,float(citizen.phase),false)
            continue
        var direction2:=(target-current).normalized()
        var direction:=Vector3(direction2.x,0.0,direction2.y)
        var next:=node.global_position+direction*float(citizen.get("speed",1.35))*delta
        var exclusions:Array[RID]=[]
        if is_instance_valid(player):exclusions.append(player.get_rid())
        var body:=citizen.get("body") as CollisionObject3D
        if is_instance_valid(body):exclusions.append(body.get_rid())
        var query:=PhysicsRayQueryParameters3D.create(node.global_position+Vector3.UP*.72,next+direction*.52+Vector3.UP*.72,1,exclusions)
        var blocked:=not space.intersect_ray(query).is_empty()
        if not blocked and (not walkable_sampler.is_valid() or bool(walkable_sampler.call(next.x,next.z))):
            node.global_position=_ground(next)
            node.look_at(node.global_position+direction,Vector3.UP)
            _animate_townsperson(node,float(citizen.phase),true)
        else:
            var center:Vector2=citizen.get("center",current)
            var turn:=direction2.rotated(1.72 if index%2==0 else -1.72)
            citizen.target=center+(current-center)*.65+turn*12.0
            citizen.pause=.4
            _animate_townsperson(node,float(citizen.phase),false)


func _animate_townsperson(node:Node3D,phase:float,moving:bool)->void:
    var swing:=sin(phase*7.5)*(.40 if moving else .025)
    for name in ["CitizenLegL","CitizenArmR"]:
        var limb:=node.get_node_or_null(name) as Node3D
        if limb:limb.rotation.x=swing
    for name in ["CitizenLegR","CitizenArmL"]:
        var limb:=node.get_node_or_null(name) as Node3D
        if limb:limb.rotation.x=-swing


func _add_townfolk(site:Dictionary,count:int)->void:
    var center:Vector2=site.get("position",Vector2.ZERO)
    var colors:=[Color(.27,.38,.22),Color(.38,.20,.16),Color(.16,.29,.42),Color(.42,.34,.14)]
    for i in range(count):
        var angle:=float(i)*TAU/float(count)+.42
        var distance:=42.0+float(i%3)*11.0
        var p:=center+Vector2(cos(angle),sin(angle))*distance
        var citizen:=Node3D.new();citizen.name="Townsperson_%d"%i;add_child(citizen);citizen.global_position=_ground(Vector3(p.x,0,p.y));citizen.rotation.y=-angle+PI*.5
        citizen.scale=Vector3.ONE*(.88+float(i%3)*.035)
        citizen.set_meta("always_streamed",true)
        _add_service_person(citizen,colors[i%colors.size()],false)
        var body:=AnimatableBody3D.new();body.name="TownspersonCollision";body.collision_layer=1;body.collision_mask=0;body.sync_to_physics=true;citizen.add_child(body)
        var shape_node:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.30;capsule.height=1.72;shape_node.shape=capsule;shape_node.position=Vector3(0,.88,0);body.add_child(shape_node)
        _townfolk.append({
            "node":citizen,"body":body,"center":center,"radius":maxf(26.0,float(site.get("radius",54.0))*.72),
            "target":center+Vector2(cos(angle+.8),sin(angle+.8))*distance,"pause":rng.randf_range(.2,2.4),
            "phase":float(i)*1.37,"speed":1.25+float(i%3)*.16,
        })


func _add_service_person(root:Node3D,cloth:Color,vendor:bool)->void:
    # Background townsfolk used to instantiate the full hero model (hundreds
    # of surfaces each). This eight-surface silhouette is readable at town
    # scale and makes dozens of NPCs cheaper than one old copy.
    var skin:=Color(.62,.43,.29)
    var leather:=Color(.19,.115,.055)
    var torso:=CapsuleMesh.new();torso.radius=.27;torso.height=1.12;torso.radial_segments=8;torso.rings=3
    var body:=MeshInstance3D.new();body.mesh=torso;body.position=Vector3(0,1.15,0);body.material_override=_service_material(cloth);body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(body)
    var head_mesh:=SphereMesh.new();head_mesh.radius=.24;head_mesh.height=.48;head_mesh.radial_segments=8;head_mesh.rings=4
    var head:=MeshInstance3D.new();head.mesh=head_mesh;head.position=Vector3(0,1.94,0);head.material_override=_service_material(skin);head.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(head)
    var hair:=MeshInstance3D.new();hair.mesh=head_mesh;hair.position=Vector3(0,2.07,-.015);hair.scale=Vector3(1.04,.48,1.04);hair.material_override=_service_material(Color(.12,.075,.04));hair.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(hair)
    _service_box(root,Vector3(0,1.08,.275),Vector3(.50,.11,.045),Color(.18,.10,.045)).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var limb_mesh:=CapsuleMesh.new();limb_mesh.radius=.075;limb_mesh.height=.72;limb_mesh.radial_segments=6;limb_mesh.rings=2
    for x in [-.16,.16]:
        var leg:=MeshInstance3D.new();leg.name="CitizenLegL" if x<0 else "CitizenLegR";leg.mesh=limb_mesh;leg.position=Vector3(x,.42,0);leg.material_override=_service_material(leather);leg.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(leg)
    for x in [-.34,.34]:
        var arm:=MeshInstance3D.new();arm.name="CitizenArmL" if x<0 else "CitizenArmR";arm.mesh=limb_mesh;arm.position=Vector3(x,1.18,0);arm.rotation.z=.12*(1.0 if x<0 else -1.0);arm.material_override=_service_material(cloth.darkened(.12));arm.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(arm)
    if vendor:
        _service_box(root,Vector3(0,1.18,.255),Vector3(.46,.54,.035),cloth.lightened(.12)).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_vendor_counter(root:Node3D,kind:String,color:Color)->void:
    var wood:=Color(.28,.16,.07)
    _service_box(root,Vector3(0,.72,-1.08),Vector3(3.5,1.15,.72),wood)
    _service_box(root,Vector3(0,1.34,-1.08),Vector3(3.8,.16,.90),Color(.38,.23,.10))
    for x in [-1.35,1.35]:_service_box(root,Vector3(x,2.35,-1.12),Vector3(.12,2.1,.12),wood)
    _service_box(root,Vector3(0,3.34,-1.12),Vector3(4.1,.16,1.15),color)
    if kind=="alchemist":
        for x in [-.72,0.0,.72]:_service_rock(root,Vector3(x,1.60,-1.05),Vector3(.28,.42,.28),Color(.38,.18+.16*(x+.72),.58))
    elif kind in ["armorer","rime_smith","skeld_smith","ember_smith"]:
        _service_box(root,Vector3(-.55,1.72,-1.05),Vector3(.72,.82,.12),Color(.48,.52,.56));_service_box(root,Vector3(.55,1.62,-1.05),Vector3(.16,.95,.10),Color(.68,.70,.72))
        if kind in ["rime_smith","skeld_smith"]:_service_rock(root,Vector3(0,1.58,-1.15),Vector3(.36,.26,.24),Color(.30,.62,.74) if kind=="rime_smith" else Color(.42,.51,.54))
        elif kind=="ember_smith":_service_rock(root,Vector3(0,1.58,-1.15),Vector3(.38,.27,.24),Color(.82,.24,.055))
    elif kind in ["grain_factor","saltmonger"]:
        for x in [-.72,-.24,.24,.72]:
            _service_box(root,Vector3(x,1.58,-1.05),Vector3(.34,.24,.34),Color(.62,.46,.19) if kind=="grain_factor" else Color(.78,.72,.56))
    elif kind=="skeld_netwright":
        for x in [-.72,-.24,.24,.72]:
            var cord_color:=Color(.33,.25,.13) if x<0.0 else Color(.52,.47,.32)
            _service_box(root,Vector3(x,1.58,-1.05),Vector3(.34,.18,.34),cord_color)
    elif kind in ["skeld_harbormaster","rime_warden"]:
        _service_box(root,Vector3(-.58,1.56,-1.05),Vector3(.66,.20,.46),Color(.74,.66,.43))
        _service_rock(root,Vector3(.50,1.72,-1.05),Vector3(.32,.46,.32),Color(.42,.75,.86))
    elif kind=="arcanist":
        _service_rock(root,Vector3(0,1.72,-1.05),Vector3(.42,.58,.42),Color(.18,.58,1.0))
    elif kind=="glacial_outfitter":
        for x in [-.72,0.0,.72]:_service_box(root,Vector3(x,1.54,-1.05),Vector3(.52,.30,.30),Color(.50,.45,.37) if x<.5 else Color(.33,.43,.45))
    else:
        for x in [-.75,-.25,.25,.75]:_service_rock(root,Vector3(x,1.55,-1.05),Vector3(.28,.22,.28),Color(.48,.66,.18) if x<0 else Color(.72,.42,.12))

func _service_box(root:Node3D,pos:Vector3,size:Vector3,color:Color)->MeshInstance3D:
    var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.position=pos;mesh.material_override=_service_material(color);root.add_child(mesh)
    return mesh


func _service_solid_box(root:Node3D,pos:Vector3,size:Vector3,color:Color)->StaticBody3D:
    var body:=StaticBody3D.new();body.position=pos;body.collision_layer=1;root.add_child(body)
    var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=_service_material(color);body.add_child(mesh)
    var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision)
    return body


func _service_material(color:Color)->StandardMaterial3D:
    var key:=color.to_html(true)
    if _service_material_cache.has(key):return _service_material_cache[key]
    var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=1.0;_service_material_cache[key]=material;return material


func _service_rock(root:Node3D,pos:Vector3,size:Vector3,color:Color)->void:
    var mesh:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=1.0;sphere.height=2.0;sphere.radial_segments=12;sphere.rings=7;mesh.mesh=sphere;mesh.position=pos;mesh.scale=size*0.5;mesh.material_override=_service_material(color);root.add_child(mesh)

func _tick_vendor()->void:
    nearby_vendor=""
    nearby_vendor_data={}
    _nearby_portal={}
    _nearby_interactable={}
    _nearby_loot={}
    _nearby_world_tree={}
    _nearby_world_rock={}
    if is_instance_valid(player) and player.has_method("is_mounted") and player.is_mounted():
        nearby_vendor="E — Dismount  |  Shift — Gallop"
        return
    if _portal_cooldown <= 0.0:
        _nearby_portal=_find_available_portal()
        if not _nearby_portal.is_empty():
            nearby_vendor="E - %s"%_nearby_portal.get("label","Enter")
            return
    var closest_interaction:=INF
    for interaction in _interactables:
        if str(interaction.get("action",""))=="mount_horse":
            var interaction_horse:=interaction.get("node") as Node3D
            interaction.active=is_instance_valid(interaction_horse) and not bool(interaction_horse.get_meta("mounted",false))
            if is_instance_valid(interaction_horse):interaction.position=interaction_horse.global_position
        if not interaction.get("active",true):continue
        var interaction_position:Vector3=interaction.get("position",Vector3.ZERO)
        var distance:=interaction_position.distance_squared_to(player.global_position)
        var radius:float=float(interaction.get("radius",4.0))
        if distance<=radius*radius and distance<closest_interaction:
            closest_interaction=distance
            _nearby_interactable=interaction
    # A dropped reward can land beside a quest prop (notably a Barrowfen ward
    # seal). Let the closest object win so pressing E over a coin pouch does
    # not unexpectedly advance the nearby objective instead of picking it up.
    if not _nearby_interactable.is_empty():
        var closest_overlapping_loot:=INF
        for dropped in loot:
            if not is_instance_valid(dropped.get("node")):continue
            var loot_distance:float=dropped.node.global_position.distance_squared_to(player.global_position)
            if loot_distance<16.0 and loot_distance<closest_overlapping_loot:
                closest_overlapping_loot=loot_distance
                _nearby_loot=dropped
        if not _nearby_loot.is_empty() and closest_overlapping_loot<closest_interaction:
            _nearby_interactable={}
            nearby_vendor="E - PICK UP %s"%str(_nearby_loot.get("reward",{}).get("name","item")).to_upper()
            return
    if _nearby_interactable.is_empty():
        _nearby_interactable=_natural_fishing_interaction()
    if not _nearby_interactable.is_empty():
        nearby_vendor="E — %s"%_nearby_interactable.get("label","Interact")
        return
    _nearby_world_tree=_find_nearby_world_tree()
    if not _nearby_world_tree.is_empty():
        nearby_vendor="E — Chop tree with equipped Axe"
        return
    _nearby_world_rock=_find_nearby_world_rock()
    if not _nearby_world_rock.is_empty():
        nearby_vendor="E — Mine rock with equipped Pickaxe"
        return
    var closest_loot:=INF
    for dropped in loot:
        if not is_instance_valid(dropped.get("node")):continue
        var loot_distance:float=dropped.node.global_position.distance_squared_to(player.global_position)
        if loot_distance<16.0 and loot_distance<closest_loot:
            closest_loot=loot_distance
            _nearby_loot=dropped
    if not _nearby_loot.is_empty():
        nearby_vendor="E - PICK UP %s"%str(_nearby_loot.get("reward",{}).get("name","item")).to_upper()
        return
    for child in _vendors:
        if child.has_meta("vendor_data") and child.global_position.distance_to(player.global_position)<5.2:
            nearby_vendor_data=child.get_meta("vendor_data")
            nearby_vendor="E — Browse %s"%nearby_vendor_data.get("type_name","merchant")
            break


func _natural_fishing_interaction()->Dictionary:
    if not is_instance_valid(player):return {}
    var point:=Vector2(player.global_position.x,player.global_position.z)
    for pond in profile.get("pond_sites",[]):
        var center:Vector2=pond.get("position",Vector2.ZERO)
        # Match the irregular radius used by the rendered pond. The previous
        # circular band missed players standing beside a lobe or inlet.
        var offset:=point-center
        var angle:=atan2(offset.y,offset.x)
        var base_radius:=float(pond.get("radius",70.0))*1.18
        var irregularity:=1.0+sin(angle*3.0+center.x*.0017)*.11+sin(angle*7.0+center.y*.0011)*.055
        var edge:=base_radius*irregularity
        var distance:=point.distance_to(center)
        # Leave a little tolerance beyond the rendered shoreline. Terrain
        # sampling and player collision can place the hero a fraction outside
        # the mathematical edge even while their feet visibly touch the bank.
        if distance>=edge-3.0 and distance<=edge+7.0:
            var inward:=offset.normalized() if offset.length_squared()>.001 else Vector2.RIGHT
            var pond_target:=center+inward*(edge-2.5)
            return {"action":"fish","position":player.global_position,"water_position":Vector3(pond_target.x,float(pond.get("water_height",1.2))+.12,pond_target.y),"radius":4.0,"label":"Cast into pond" if player.has_fishing_pole_equipped() else "Equip Fishing Pole to fish","active":true,"natural":true}
    for river in profile.get("river_corridors",[]):
        var width:=float(river.get("width",48.0))
        var distance:=_distance_to_polyline_2d(point,river.get("points",[]))
        if distance>=width*.40-2.0 and distance<=width*.42+5.0:
            var river_center:=_closest_point_on_polyline_2d(point,river.get("points",[]))
            var bank_direction:=(point-river_center).normalized() if point.distance_squared_to(river_center)>.001 else Vector2.RIGHT
            var river_target:=river_center+bank_direction*width*.36
            return {"action":"fish","position":player.global_position,"water_position":Vector3(river_target.x,_river_surface_y(river_target.x),river_target.y),"radius":4.0,"label":"Cast into river" if player.has_fishing_pole_equipped() else "Equip Fishing Pole to fish","active":true,"natural":true}
    return {}


func _distance_to_polyline_2d(point:Vector2,points:Array)->float:
    if points.size()<2:return INF
    var best:=INF
    for i in range(points.size()-1):
        var a:Vector2=points[i]
        var b:Vector2=points[i+1]
        var delta:=b-a
        var closest:=a if delta.length_squared()<.0001 else a+delta*clampf((point-a).dot(delta)/delta.length_squared(),0.0,1.0)
        best=minf(best,point.distance_to(closest))
    return best


func _closest_point_on_polyline_2d(point:Vector2,points:Array)->Vector2:
    if points.size()<2:return point
    var best_point:Vector2=points[0]
    var best_distance:=INF
    for i in range(points.size()-1):
        var a:Vector2=points[i]
        var b:Vector2=points[i+1]
        var delta:=b-a
        var closest:=a if delta.length_squared()<.0001 else a+delta*clampf((point-a).dot(delta)/delta.length_squared(),0.0,1.0)
        var distance:=point.distance_squared_to(closest)
        if distance<best_distance:
            best_distance=distance
            best_point=closest
    return best_point


func _find_available_portal()->Dictionary:
    if _portal_cooldown>0.0 or not is_instance_valid(player):return {}
    for portal in _portals:
        if portal.get("action","travel")=="chest" and portal.get("looted",false):continue
        if portal.get("action","")=="dungeon_key" and portal.get("collected",false):continue
        if portal.get("action","")=="dungeon_door" and portal.get("unlocked",false):continue
        var portal_position:Vector3=portal.get("position",Vector3.ZERO)
        var portal_radius:float=portal.get("radius",4.5)
        var in_range:=false
        if portal.get("horizontal",false):
            var portal_xz:=Vector2(portal_position.x,portal_position.z)
            var player_xz:=Vector2(player.global_position.x,player.global_position.z)
            in_range=portal_xz.distance_squared_to(player_xz)<=portal_radius*portal_radius
        else:
            in_range=portal_position.distance_squared_to(player.global_position)<=portal_radius*portal_radius
        if in_range:return portal
    return {}


func _tick_auto_portal()->void:
    if _portal_cooldown>0.0 or not is_instance_valid(player):return
    var player_xz:=Vector2(player.global_position.x,player.global_position.z)
    for portal in _portals:
        if not portal.get("auto_enter",false) or portal.get("action","travel")!="travel":continue
        var portal_position:Vector3=portal.get("position",Vector3.ZERO)
        var radius:float=float(portal.get("auto_radius",6.0))
        if player_xz.distance_squared_to(Vector2(portal_position.x,portal_position.z))<=radius*radius:
            _activate_portal(portal)
            return

func _activate_portal(portal:Dictionary)->void:
    var action:String=portal.get("action","travel")
    if action=="zone_travel":
        zone_travel_requested.emit(str(portal.get("target","starting_realm")),str(portal.get("entry","south")))
        return
    if action=="chest":
        _loot_dungeon_chest(portal)
        return
    if action=="dungeon_key":
        portal.collected=true
        var key_id:String=portal.get("key_id","dungeon_key")
        player.add_bag_item({"id":key_id,"slot":"key","icon":9,"name":portal.get("item_name","Dungeon Key"),"armor":0,"hp":0,"mana":0,"power":0,"description":"Opens a matching locked dungeon gate."})
        var key_node:Node=portal.get("node")
        if is_instance_valid(key_node):key_node.visible=false
        _notify("Picked up %s"%portal.get("item_name","Dungeon Key"),Color(1.0,.74,.24));_portal_cooldown=.6;return
    if action=="dungeon_door":
        var required_key:String=portal.get("key_id","")
        var key_index:=-1
        for i in range(player.bag_slots.size()):
            if player.bag_slots[i].get("id","")==required_key:key_index=i;break
        if key_index<0:
            _notify("Locked — %s required"%portal.get("item_name","key"),Color(1.0,.34,.24));_portal_cooldown=.6;return
        player.bag_slots.remove_at(key_index);portal.unlocked=true
        var door:Node=portal.get("door")
        if is_instance_valid(door):
            var tween:=create_tween();tween.tween_property(door,"position:y",door.position.y+7.0,.72).set_trans(Tween.TRANS_QUAD);tween.tween_callback(door.queue_free)
        var door_marker:Node=portal.get("marker")
        if is_instance_valid(door_marker):door_marker.visible=false
        _notify("Gate unlocked",Color(.64,1.0,.54));_portal_cooldown=.8;return
    var destination:Vector3=portal.get("destination",player.global_position)
    var interior:bool=portal.get("interior",false)
    if player.has_method("set_interior_mode"):player.set_interior_mode(interior)
    player.global_position=destination
    player.velocity=Vector3.ZERO
    _portal_cooldown=1.0
    _nearby_portal={}
    nearby_vendor=""


func _loot_dungeon_chest(chest_data:Dictionary)->void:
    if chest_data.get("looted",false):
        return
    var boss_gate:String=chest_data.get("boss_gate","")
    if not boss_gate.is_empty() and _boss_alive(boss_gate):
        var marker_locked:Label3D=chest_data.get("marker")
        if is_instance_valid(marker_locked):marker_locked.text="DEFEAT THE CAVE DRAGON\nTO UNSEAL THE ROYAL HOARD"
        _portal_cooldown=.8
        return
    if not boss_gate.is_empty():
        var key_id:="dragon_key_%s"%boss_gate;var key_index:=-1
        for i in range(player.bag_slots.size()):
            if player.bag_slots[i].get("id","")==key_id:key_index=i;break
        if key_index<0:
            var marker_key:Label3D=chest_data.get("marker")
            if is_instance_valid(marker_key):marker_key.text="LOCKED\nDRAGON HOARD KEY REQUIRED"
            _portal_cooldown=.8;return
        player.bag_slots.remove_at(key_index)
    var rank:int=int(chest_data.get("rank",1))
    var slot:="hands"
    var item_name:="Wellwarden Gloves"
    if not boss_gate.is_empty():
        slot="chest";item_name="Dragonforged Royal Cuirass"
    elif rank==3:
        slot="chest";item_name="West Cavern Brigandine"
    elif rank>=4:
        slot="head";item_name="East Cavern Runed Helm"
    var item:={
        "kind":"item",
        "id":"dungeon_chest_%d_%d"%[rank,Time.get_ticks_msec()],
        "name":item_name,
        "slot":slot,
        "icon":3 if slot=="hands" else (1 if slot=="chest" else 0),
        "armor":5+rank*4,
        "hp":8+rank*7,
        "mana":rank*2,
        "power":2+rank*2,
        "description":"Dragonforged royal armor claimed from the sealed hoard." if not boss_gate.is_empty() else "Gear recovered from a rank %d dungeon chest."%rank,
    }
    var chest:Node3D=chest_data.get("chest")
    var drop_origin:Vector3=chest.global_position+Vector3(0,.25,2.2) if is_instance_valid(chest) else player.global_position+Vector3(0,0,-2.0)
    _spawn_world_drop(drop_origin+Vector3(-.8,0,0),item,true)
    _spawn_world_drop(drop_origin+Vector3(.8,0,0),{"kind":"gold","amount":150 if not boss_gate.is_empty() else 12+rank*9,"name":"Royal Coin Pouch"},true)
    _spawn_world_drop(drop_origin+Vector3(0,0,.75),{"kind":"material","material":"crystal" if not boss_gate.is_empty() else "essence","amount":2 if rank>=3 else 1,"name":"Dragon Crystal" if not boss_gate.is_empty() else "Dungeon Essence"},true)
    _gathered_counts.dungeons=int(_gathered_counts.get("dungeons",0))+1
    _check_quest_rewards()
    chest_data["looted"]=true
    var lid:Node3D=chest_data.get("lid")
    if is_instance_valid(lid):
        lid.rotation.x=-.72
        lid.position+=Vector3(0,.35,.48)
    var marker:Label3D=chest_data.get("marker")
    if is_instance_valid(marker):
        marker.text="OPENED\nLOOT IS ON THE FLOOR"
        marker.modulate=Color(.55,.55,.52)
    _portal_cooldown=1.2
    _nearby_portal={}
    nearby_vendor=""

func _boss_alive(boss_id:String)->bool:
    for enemy in minions:
        if enemy.get("boss_id","")==boss_id and is_instance_valid(enemy.node) and not enemy.get("dead",false):return true
    return false


func _vendor_catalog(kind:String,town:String)->Dictionary:
    if kind=="march_factor":
        return {"id":"%s_march_factor"%town,"name":"Veyra Tollhand","type_name":"Dawnford Caravan Factor","color":Color(.58,.37,.13),"greeting":"Every honest road leaves a ledger. Every useful traveler leaves with supplies.","inventory":[
            {"kind":"armor","id":"dawnway_caravan_blade","name":"Dawnway Caravan Blade","price":152,"description":"A broad road sword. Power +18, HP +7.","slot":"mainhand","visual":"sword","icon":7,"armor":0,"hp":7,"mana":0,"power":18,"max_durability":190.0},
            {"kind":"armor","id":"dawnford_toll_buckler","name":"Dawnford Toll Buckler","price":128,"description":"A compact oak-and-iron shield. Armor +12, HP +18.","slot":"offhand","visual":"shield","icon":9,"armor":12,"hp":18,"mana":0,"power":3,"max_durability":185.0},
            {"kind":"material","material":"cloth","amount":7,"name":"Ochre Caravan Canvas","price":34,"description":"Seven measures of tough marcher canvas."},
            {"kind":"repair","name":"Caravan Gear Refit","price":33,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="march_warden":
        return {"id":"%s_march_warden"%town,"name":"Marshal Teren","type_name":"March Keep Warden Stores","color":Color(.42,.35,.24),"greeting":"The bridge, the beacon, and every mile between them are kept with iron.","inventory":[
            {"kind":"armor","id":"marchwarden_lamellar_shop","name":"Marchwarden Lamellar","price":218,"description":"Basalt-iron patrol armor. Armor +21, HP +31, Power +5.","slot":"chest","visual":"chest","icon":1,"armor":21,"hp":31,"mana":0,"power":5,"max_durability":215.0},
            {"kind":"armor","id":"saltmeadow_roundshield_shop","name":"Saltmeadow Roundshield","price":184,"description":"A poplar and basalt-iron shield. Armor +15, HP +24.","slot":"offhand","visual":"shield","icon":9,"armor":15,"hp":24,"mana":0,"power":4,"max_durability":205.0},
            {"kind":"material","material":"ore","amount":8,"name":"March Keep Basalt Iron","price":52,"description":"Eight billets of dark marcher iron."},
            {"kind":"repair","name":"Warden Full Gear Repair","price":41,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="ember_smith":
        return {"id":"%s_ember_smith"%town,"name":"Sava Emberhand","type_name":"Cinderwatch Signal Forge","color":Color(.47,.22,.09),"greeting":"Emberglass remembers heat. Basalt iron remembers the hammer. Both remember an oath.","inventory":[
            {"kind":"armor","id":"cinderwatch_signal_blade","name":"Cinderwatch Signal Blade","price":226,"description":"A basalt-iron longsword. Power +24, Armor +2.","slot":"mainhand","visual":"sword","icon":7,"armor":2,"hp":8,"mana":0,"power":24,"max_durability":225.0},
            {"kind":"armor","id":"emberglass_oath_band_shop","name":"Emberglass Oath Band","price":246,"description":"A living emberglass ring. HP +14, Mana +8, Power +10.","slot":"ring_right","visual":"magic ring","ring_design":"split_band","effect":"emberpulse","icon":10,"armor":3,"hp":14,"mana":8,"power":10,"max_durability":210.0},
            {"kind":"material","material":"crystal","amount":4,"name":"Warm Emberglass Shards","price":76,"description":"Four heat-bright fragments from Embercrag."},
            {"kind":"repair","name":"Signal-Forge Gear Repair","price":43,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="grain_factor":
        return {"id":"%s_grain_factor"%town,"name":"Mera Goldsheaf","type_name":"Amberfield Grain Exchange","color":Color(.59,.45,.14),"greeting":"A road army marches on grain before iron. Take enough for the return journey.","inventory":[
            {"kind":"health_potion","name":"Amberfield Restorative","price":27,"description":"Adds one health potion."},
            {"kind":"armor","id":"amberfield_drovers_boots","name":"Amberfield Drover's Boots","price":126,"description":"High ochre road boots. Armor +7, HP +16, Power +3.","slot":"feet","visual":"boots","icon":4,"armor":7,"hp":16,"mana":0,"power":3,"max_durability":180.0},
            {"kind":"material","material":"herbs","amount":7,"name":"Amber Sage Bundle","price":29,"description":"Seven measures of dry marcher sage."},
            {"kind":"material","material":"leather","amount":6,"name":"Drover Leather Roll","price":35,"description":"Six pieces of road-cured leather."}
        ]}
    if kind=="saltmonger":
        return {"id":"%s_saltmonger"%town,"name":"Orra Reedwise","type_name":"Saltwatch Meadow Trade","color":Color(.50,.49,.34),"greeting":"Salt keeps meat, leather, and promises from spoiling on the north road.","inventory":[
            {"kind":"armor","id":"saltwatch_reedcloak","name":"Saltwatch Reedcloak","price":158,"description":"A pale meadow cloak. Armor +8, HP +21, Mana +4.","slot":"shoulders","visual":"shoulders","icon":2,"armor":8,"hp":21,"mana":4,"power":3,"max_durability":190.0},
            {"kind":"health_potion","name":"Glassmere Bitter Tonic","price":28,"description":"Adds one health potion."},
            {"kind":"material","material":"resin","amount":7,"name":"Salt-Cured Lamp Resin","price":37,"description":"Seven measures of slow-burning meadow resin."},
            {"kind":"material","material":"cloth","amount":7,"name":"Reed-Woven Cloth Roll","price":34,"description":"Seven measures of tough pale cloth."}
        ]}
    if kind=="skeld_harbormaster":
        return {"id":"%s_skeld_harbormaster"%town,"name":"Sigrun Tideward","type_name":"Frostharbor Harbour Office","color":Color(.15,.31,.36),"greeting":"Cape Keld names the channel. Frostharbor decides who may use it.","inventory":[
            {"kind":"armor","id":"frostharbor_saltsteel_harpoon_shop","name":"Frostharbor Saltsteel Harpoon","price":236,"description":"A long coastal point. Power +23, Armor +2, HP +10.","slot":"mainhand","visual":"sword","icon":7,"armor":2,"hp":10,"mana":0,"power":23,"max_durability":230.0},
            {"kind":"armor","id":"cape_keld_watchcoat_shop","name":"Cape Keld Watchcoat","price":248,"description":"A warded lightkeeper coat. Armor +17, HP +36, frostward.","slot":"chest","visual":"chest","effect":"frostward","icon":1,"armor":17,"hp":36,"mana":6,"power":5,"max_durability":225.0},
            {"kind":"material","material":"crystal","amount":4,"name":"Lantern Sea-Glass Crate","price":74,"description":"Four pieces of cold sea-glass recovered below Cape Keld."},
            {"kind":"repair","name":"Harbour Gear Overhaul","price":44,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="skeld_netwright":
        return {"id":"%s_skeld_netwright"%town,"name":"Asta Netmaker","type_name":"Skeld Nets & Provisions","color":Color(.27,.36,.31),"greeting":"A sound net feeds a hall. A sound rope brings you home.","inventory":[
            {"kind":"armor","id":"kelpwick_sealhide_boots","name":"Kelpwick Sealhide Boots","price":142,"description":"Waxed coastal boots. Armor +8, HP +18, Power +3.","slot":"feet","visual":"boots","icon":4,"armor":8,"hp":18,"mana":0,"power":3,"max_durability":190.0},
            {"kind":"armor","id":"skeld_fishing_pole","name":"Skeld Fishing Pole","price":96,"description":"A salt-sealed ash fishing pole built for river mouths and ocean piers.","slot":"mainhand","visual":"fishing pole","icon":8,"armor":0,"hp":2,"mana":0,"power":4,"max_durability":170.0},
            {"kind":"material","material":"cloth","amount":8,"name":"Tarred Net Cord","price":38,"description":"Eight measures of strong tarred cord."},
            {"kind":"health_potion","name":"Juniper Fish Broth","price":31,"description":"Adds one health potion."}
        ]}
    if kind=="rime_warden":
        return {"id":"%s_rime_warden"%town,"name":"Hakon Rimeward","type_name":"Vardholm Rimepass Stores","color":Color(.31,.37,.40),"greeting":"The east road climbs into ice. The south road falls into thunder. Choose with supplies.","inventory":[
            {"kind":"armor","id":"vardholm_watchcoat_shop","name":"Vardholm Sealhide Watchcoat","price":224,"description":"A cold-weather road coat. Armor +16, HP +34, frostward.","slot":"chest","visual":"chest","effect":"frostward","icon":1,"armor":16,"hp":34,"mana":4,"power":4,"max_durability":215.0},
            {"kind":"armor","id":"greywake_lantern_band_shop","name":"Greywake Lantern Band","price":268,"description":"A sea-glass ward ring. HP +18, Mana +14, Power +9.","slot":"ring_left","visual":"magic ring","ring_design":"split_band","effect":"frostward","icon":10,"armor":5,"hp":18,"mana":14,"power":9,"max_durability":220.0},
            {"kind":"material","material":"resin","amount":8,"name":"Rimepass Fire Pitch","price":48,"description":"Eight measures of slow-burning coastal pitch."},
            {"kind":"health_potion","name":"Vardholm Warming Draught","price":34,"description":"Adds one health potion."}
        ]}
    if kind=="skeld_smith":
        return {"id":"%s_skeld_smith"%town,"name":"Torvi Saltiron","type_name":"Vardholm Saltsteel Forge","color":Color(.38,.40,.41),"greeting":"Sea salt ruins weak iron. Mine leaves the forge expecting it.","inventory":[
            {"kind":"armor","id":"vardholm_saltsteel_helm","name":"Vardholm Saltsteel Helm","price":182,"description":"A close coastal helm. Armor +14, HP +18, Power +3.","slot":"head","icon":0,"armor":14,"hp":18,"mana":0,"power":3,"max_durability":225.0},
            {"kind":"armor","id":"skeld_breakwater_shield","name":"Skeld Breakwater Shield","price":214,"description":"A tarred oak and saltsteel shield. Armor +17, HP +30.","slot":"offhand","visual":"shield","icon":9,"armor":17,"hp":30,"mana":0,"power":4,"max_durability":240.0},
            {"kind":"material","material":"ore","amount":9,"name":"Vardholm Saltsteel Crate","price":62,"description":"Nine pieces of coast-worked iron ore."},
            {"kind":"repair","name":"Saltsteel Full Gear Repair","price":45,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="storm_warden":
        return {"id":"%s_storm_warden"%town,"name":"Cael Stormward","type_name":"Stormbreak Warden Stores","color":Color(.28,.35,.34),"greeting":"Three roads meet here. Carry enough steel to return by any one of them.","inventory":[
            {"kind":"armor","id":"stormward_patrol_mantle_shop","name":"Stormward Patrol Mantle","price":176,"description":"A highland road mantle. Armor +9, HP +20, Power +5, windstep.","slot":"shoulders","visual":"shoulders","effect":"windstep","icon":2,"armor":9,"hp":20,"mana":0,"power":5,"max_durability":180.0},
            {"kind":"armor","id":"galehorn_road_spear_shop","name":"Galehorn Road Spear","price":184,"description":"A long highland blade. Power +20, Armor +2, HP +8.","slot":"mainhand","visual":"sword","icon":7,"armor":2,"hp":8,"mana":0,"power":20,"max_durability":205.0},
            {"kind":"material","material":"resin","amount":7,"name":"Beacon Fire Resin","price":42,"description":"Seven measures of highland fire resin."},
            {"kind":"repair","name":"Stormwarden Field Repair","price":36,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="highland_smith":
        return {"id":"%s_highland_smith"%town,"name":"Brenn Slatehand","type_name":"Stormbreak Highland Forge","color":Color(.38,.39,.37),"greeting":"Wind cools iron quickly. That is why ours remembers the hammer.","inventory":[
            {"kind":"armor","id":"stormbreak_slate_cuirass","name":"Stormbreak Slate Cuirass","price":205,"description":"Layered highland plate. Armor +22, HP +32, Power +5.","slot":"chest","icon":1,"armor":22,"hp":32,"mana":0,"power":5,"max_durability":230.0},
            {"kind":"armor","id":"stormscar_buckler","name":"Stormscar Buckler","price":154,"description":"A black-iron road shield. Armor +14, HP +22.","slot":"offhand","visual":"shield","icon":9,"armor":14,"hp":22,"mana":0,"power":3,"max_durability":210.0},
            {"kind":"material","material":"ore","amount":8,"name":"Highland Iron Crate","price":49,"description":"Eight pieces of cold highland iron."},
            {"kind":"repair","name":"Highland Full Gear Repair","price":38,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="peatwright":
        return {"id":"%s_peatwright"%town,"name":"Eira Moorwise","type_name":"Moorwatch Peat & Wool","color":Color(.39,.31,.20),"greeting":"Dry fuel, warm wool, and no promises about the weather.","inventory":[
            {"kind":"armor","id":"moorwatch_wool_coat","name":"Moorwatch Wool Coat","price":148,"description":"A weatherproof coat. Armor +8, HP +24, Mana +5.","slot":"chest","icon":1,"armor":8,"hp":24,"mana":5,"power":3,"max_durability":165.0},
            {"kind":"material","material":"cloth","amount":8,"name":"Storm Wool Roll","price":34,"description":"Eight measures of dense highland wool."},
            {"kind":"material","material":"resin","amount":6,"name":"Peat-Fire Pitch","price":31,"description":"Six measures of slow-burning pitch."},
            {"kind":"health_potion","name":"Moorwatch Warming Tonic","price":27,"description":"Adds one health potion."}
        ]}
    if kind=="drover":
        return {"id":"%s_drover"%town,"name":"Tarin Cairnroad","type_name":"Cairnstead Drover Market","color":Color(.42,.34,.17),"greeting":"What survives Galehorn weather will survive most roads.","inventory":[
            {"kind":"armor","id":"cairnstead_trail_boots","name":"Cairnstead Trail Boots","price":116,"description":"Hobnailed road boots. Armor +7, HP +14, Power +3.","slot":"feet","visual":"boots","icon":4,"armor":7,"hp":14,"mana":0,"power":3,"max_durability":175.0},
            {"kind":"armor","id":"blacktarn_compass_band_shop","name":"Blacktarn Compass Band","price":198,"description":"A frostward compass ring. Mana +10, Power +7.","slot":"ring_left","visual":"magic ring","ring_design":"crown","effect":"frostward","icon":10,"armor":4,"hp":14,"mana":10,"power":7,"max_durability":190.0},
            {"kind":"material","material":"leather","amount":7,"name":"Drover Hide Bundle","price":38,"description":"Seven pieces of road-cured leather."},
            {"kind":"material","material":"logs","amount":6,"name":"Shelter Timber Bundle","price":30,"description":"Six lengths of dry highland timber."}
        ]}
    if kind=="woodwright":
        return {"id":"%s_woodwright"%town,"name":"Edda Rainsaw","type_name":"Oakrest Woodwright","color":Color(.38,.29,.12),"greeting":"Western oak bends before it breaks. Good gear should do the same.","inventory":[
            {"kind":"armor","id":"rainward_forester_axe","name":"Rainward Forester Axe","price":118,"description":"A balanced felling axe. Power +13, HP +6.","slot":"mainhand","visual":"axe","icon":8,"armor":0,"hp":6,"mana":0,"power":13,"max_durability":165.0},
            {"kind":"armor","id":"waxed_oak_shield","name":"Waxed Oak Shield","price":102,"description":"A resin-sealed road shield. Armor +11, HP +20.","slot":"offhand","visual":"shield","icon":9,"armor":11,"hp":20,"mana":0,"power":2,"max_durability":180.0},
            {"kind":"material","material":"logs","amount":8,"name":"Seasoned Oak Bundle","price":30,"description":"Eight dry Oakrest timbers."},
            {"kind":"material","material":"resin","amount":5,"name":"Rainproof Resin","price":26,"description":"Five measures of boiled wood resin."}
        ]}
    if kind=="river_trader":
        return {"id":"%s_river_trader"%town,"name":"Hale Fenwick","type_name":"Rainhaven River Trade","color":Color(.16,.36,.39),"greeting":"If it crossed the Rainfall dry, it was packed here.","inventory":[
            {"kind":"health_potion","name":"Rainhaven Bitter Tonic","price":22,"description":"Adds one health potion."},
            {"kind":"armor","id":"rainhaven_wading_boots","name":"Rainhaven Wading Boots","price":88,"description":"Waxed high boots. Armor +5, HP +14, Power +2.","slot":"feet","visual":"boots","icon":4,"armor":5,"hp":14,"mana":0,"power":2,"max_durability":150.0},
            {"kind":"armor","id":"tideglass_traders_band","name":"Tideglass Trader's Band","price":142,"description":"A river-glass ring. Mana +7, Power +6, windstep.","slot":"ring_left","visual":"magic ring","ring_design":"spiral","effect":"windstep","icon":10,"armor":2,"hp":8,"mana":7,"power":6,"max_durability":165.0},
            {"kind":"material","material":"cloth","amount":6,"name":"Waxed Sailcloth Roll","price":31,"description":"Six measures of weatherproof cloth."}
        ]}
    if kind=="quarry_mason":
        return {"id":"%s_quarry_mason"%town,"name":"Torren Flint","type_name":"Stonecross Masonry","color":Color(.39,.40,.35),"greeting":"Good stone, honest iron, and nothing that rattles loose on a mountain road.","inventory":[
            {"kind":"armor","id":"stonecross_masons_jack","name":"Stonecross Mason's Jack","price":154,"description":"Quarry plate. Armor +17, HP +28, Power +3.","slot":"chest","icon":1,"armor":17,"hp":28,"mana":0,"power":3,"max_durability":195.0},
            {"kind":"armor","id":"stonecross_pick","name":"Stonecross War Pick","price":126,"description":"A compact iron pick. Power +15, Armor +2.","slot":"mainhand","visual":"pickaxe","icon":8,"armor":2,"hp":0,"mana":0,"power":15,"max_durability":180.0},
            {"kind":"material","material":"stone","amount":8,"name":"Dressed Stone Stack","price":28,"description":"Eight squared blocks for advanced crafting."},
            {"kind":"repair","name":"Mason's Full Gear Repair","price":29,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="glacial_outfitter":
        return {"id":"%s_outfitter"%town,"name":"Tova Icewise","type_name":"Glacial Outfitter","color":Color(.20,.40,.46),"greeting":"The high ice punishes poor preparation. Take what keeps you alive.","inventory":[
            {"kind":"health_potion","name":"Icewatch Warming Tonic","price":28,"description":"Adds one health potion."},
            {"kind":"armor","id":"icewatch_fur_mantle","name":"Icewatch Fur Mantle","price":124,"description":"A layered expedition mantle. Armor +7, HP +18, frostward.","slot":"shoulders","visual":"shoulders","effect":"frostward","icon":2,"armor":7,"hp":18,"mana":2,"power":3,"max_durability":150.0},
            {"kind":"armor","id":"surveyors_climbing_boots","name":"Surveyor's Climbing Boots","price":92,"description":"Hobnailed glacial boots. Armor +6, HP +10, Power +3.","slot":"feet","visual":"boots","icon":4,"armor":6,"hp":10,"mana":0,"power":3,"max_durability":145.0},
            {"kind":"material","material":"resin","amount":5,"name":"Coldproof Resin Bundle","price":32,"description":"Five measures of resin for camp and equipment crafting."}
        ]}
    if kind=="rime_smith":
        return {"id":"%s_rime_smith"%town,"name":"Orik Moraineborn","type_name":"Glacial Ironworks","color":Color(.32,.40,.43),"greeting":"Rimegate iron holds an edge where southern steel turns brittle.","inventory":[
            {"kind":"armor","id":"rimegate_glacial_sword","name":"Rimegate Glacial Sword","price":168,"description":"A glacial-iron longsword. Power +14, frostward.","slot":"mainhand","visual":"sword","effect":"frostward","icon":7,"armor":0,"hp":5,"mana":0,"power":14,"max_durability":175.0},
            {"kind":"armor","id":"moraine_guard_shield","name":"Moraine Guard Shield","price":146,"description":"A stone-rimmed expedition shield. Armor +12, HP +22.","slot":"offhand","visual":"shield","icon":9,"armor":12,"hp":22,"mana":0,"power":2,"max_durability":190.0},
            {"kind":"material","material":"ore","amount":8,"name":"Rimegate Ore Crate","price":44,"description":"Eight chunks of cold-worked ore."},
            {"kind":"repair","name":"Cold-Hammer Gear Repair","price":32,"description":"Restore all equipped ordinary gear to full durability."}
        ]}
    if kind=="alchemist":
        return {"id":"%s_alchemist"%town,"name":"Mira of %s"%town,"type_name":"Alchemy & Remedies","color":Color(.28,.15,.52),"greeting":"Elixirs, reagents, and remedies—carefully measured.","inventory":[
            {"kind":"health_potion","name":"Crimson Health Potion","price":18,"description":"Adds one health potion."},
            {"kind":"mana_potion","name":"Azure Mana Draught","price":24,"description":"Adds one mana potion."},
            {"kind":"material","material":"herbs","amount":5,"name":"Medicinal Herb Bundle","price":14,"description":"Five fresh herbs for crafting."},
            {"kind":"material","material":"essence","amount":1,"name":"Refined Arcane Essence","price":38,"description":"A rare alchemical catalyst."}
        ]}
    if kind=="armorer":
        return {"id":"%s_armorer"%town,"name":"Master Harl","type_name":"Armor & Steel","color":Color(.32,.36,.42),"greeting":"Steel fitted for the road, the river, and the battlefield.","inventory":[
            {"kind":"armor","name":"Tempered Steel Helm","price":46,"description":"Head armor. Armor +7, HP +10.","slot":"head","icon":0,"armor":7,"hp":10,"mana":0,"power":2},
            {"kind":"armor","name":"Crown Guard Cuirass","price":82,"description":"Chest armor. Armor +14, HP +25.","slot":"chest","icon":1,"armor":14,"hp":25,"mana":2,"power":5},
            {"kind":"armor","name":"Knight's Gauntlets","price":42,"description":"Hand armor. Armor +5, Power +4.","slot":"hands","icon":3,"armor":5,"hp":7,"mana":0,"power":4},
            {"kind":"armor","name":"Marching Greaves","price":40,"description":"Foot armor. Armor +5, HP +9.","slot":"feet","icon":4,"armor":5,"hp":9,"mana":0,"power":2},
            {"kind":"repair","name":"Repair Equipped Gear","price":25,"description":"Restore all equipped ordinary gear to full durability. Royal equipment never needs repair."}
        ]}
    if kind=="arcanist":
        return {"id":"%s_arcanist"%town,"name":"Archivist Selene","type_name":"Arcane Curios","color":Color(.12,.35,.58),"greeting":"The crown permits these relics to leave the archive—for a price.","inventory":[
            {"kind":"mana_potion","name":"Scholar's Mana Tonic","price":21,"description":"Adds one mana potion."},
            {"kind":"material","material":"essence","amount":2,"name":"Twin Arcane Essences","price":70,"description":"Two refined essences."},
            {"kind":"armor","name":"Runed Pauldrons","price":68,"description":"Shoulder armor. Mana +10, Power +5.","slot":"shoulders","icon":2,"armor":5,"hp":6,"mana":10,"power":5},
            {"kind":"armor","id":"wayfarer_signet","name":"Wayfarer's Signet","price":96,"description":"A wind-marked ring. Power +4 and HP +8; its magic appears while equipped.","slot":"ring_left","visual":"magic ring","effect":"windstep","icon":10,"armor":1,"hp":8,"mana":3,"power":4,"max_durability":120.0}
        ]}
    return {"id":"%s_provisioner"%town,"name":"Rowan's Trading Post","type_name":"General Provisions","color":Color(.48,.29,.08),"greeting":"Road supplies, camp goods, and honest prices.","inventory":[
        {"kind":"health_potion","name":"Traveler's Health Potion","price":18,"description":"Adds one health potion."},
        {"kind":"mana_potion","name":"Traveler's Mana Potion","price":22,"description":"Adds one mana potion."},
        {"kind":"material","material":"scrap","amount":6,"name":"Metal Scrap Bundle","price":15,"description":"Six pieces of useful scrap."},
        {"kind":"material","material":"ore","amount":4,"name":"Iron Ore Sack","price":20,"description":"Four chunks of iron ore."}
    ]}

func purchase_vendor_item(vendor_data:Dictionary,index:int)->String:
    var inventory:Array=vendor_data.get("inventory",[])
    if index<0 or index>=inventory.size():return "That item is unavailable."
    var item:Dictionary=inventory[index]
    var price:int=int(item.get("price",0))
    if item.get("kind","")=="repair" and player.get_repair_cost()<=0:return "Your equipped gear is already in good repair."
    if player.hero_gold<price:return "You do not have enough gold."
    if item.get("kind","")=="armor" and player.bag_slots.size()>=80:return "Your armor bag is full."
    player.hero_gold-=price
    match item.get("kind",""):
        "health_potion":player.health_potions+=1
        "mana_potion":player.mana_potions+=1
        "material":
            var amount:int=int(item.get("amount",1));var material_name:String=str(item.get("material","herbs"));player.add_material(material_name,amount)
        "armor":
            var armor_item:=item.duplicate(true)
            if str(armor_item.get("id","")).is_empty():armor_item["id"]="shop_%s_%d"%[item.get("slot","armor"),Time.get_ticks_msec()]
            armor_item.erase("kind");armor_item.erase("price");player.add_bag_item(armor_item)
        "repair":player.repair_all_equipment()
    return "Purchased %s for %d gold."%[item.get("name","item"),price]

func _spawn_loot(pos:Vector3,elite:bool,rank:int=1,boss:bool=false)->void:
    var material_pool:=["herbs","scrap","ore","leather","cloth","resin","mushrooms","stone"]
    var material_kind:String=material_pool[rng.randi_range(0,material_pool.size()-1)]
    _spawn_world_drop(pos,{"kind":"material","material":material_kind,"amount":2 if elite else 1,"name":material_kind.capitalize()},elite)
    _spawn_world_drop(pos+Vector3(.55,0,.35),{"kind":"gold","amount":40 if boss else (7 if elite else 2),"name":"Gold Coins"},elite)
    if boss or (elite and rng.randf()<.18):
        var ring_pool:Array[Dictionary]=[
            {"id":"glacier_heart_ring_%d"%rng.randi(),"name":"Glacier-Heart Ring","effect":"frostward","ring_design":"crown","armor":3,"hp":14,"mana":8,"power":3,"description":"A crown-set silver ring cold to the touch. Its frostward becomes visible when equipped."},
            {"id":"emberglass_band_%d"%rng.randi(),"name":"Emberglass Band","effect":"emberpulse","ring_design":"split_band","armor":1,"hp":8,"mana":3,"power":7,"description":"A split iron band holding warm emberglass. Its pulse becomes visible when equipped."},
            {"id":"wayfarer_loop_%d"%rng.randi(),"name":"Wayfarer's Loop","effect":"windstep","ring_design":"spiral","armor":1,"hp":10,"mana":5,"power":5,"description":"An open spiral ring etched with the roads of the old realm."},
        ]
        var ring:=ring_pool[rng.randi_range(0,ring_pool.size()-1)].duplicate(true)
        ring.merge({"kind":"item","slot":"ring_left","visual":"magic ring","icon":10,"max_durability":120.0},true)
        _spawn_world_drop(pos+Vector3(0,0,-.72),ring,true)
    if boss or rng.randf()<(.42 if elite else .12):
        var slots:=["head","chest","hands","feet","pants","mainhand","offhand"]
        var slot:String=slots[rng.randi_range(0,slots.size()-1)]
        var names:={"head":"King's Guard Helm","chest":"Monster King's Warplate","hands":"Clawed Gauntlets","feet":"Dreadmarch Boots","pants":"Scaled War Trousers","mainhand":"Monster King's Cleaver","offhand":"Trophy Crest Shield"}
        var gear:={"kind":"item","name":names[slot],"slot":slot,"icon":8 if slot=="mainhand" else (9 if slot=="offhand" else (1 if slot=="chest" else 0)),"armor":(5+rank*3) if slot not in ["mainhand"] else 0,"hp":5+rank*6,"mana":rank,"power":4+rank*3,"description":"Visible trophy gear recovered from a powerful monster."}
        _spawn_world_drop(pos+Vector3(-.55,0,.25),gear,true)
    if boss:
        for extra in ["crystal","essence","leather"]:_spawn_world_drop(pos+Vector3(rng.randf_range(-1.2,1.2),0,rng.randf_range(-1.2,1.2)),{"kind":"material","material":extra,"amount":2,"name":extra.capitalize()},true)
    if str(profile.get("zone_id",""))=="east_marches" and (elite or rng.randf()<.18):
        var marcher_reward:Dictionary
        if elite and rng.randf()<.28:
            marcher_reward={"kind":"item","id":"cinderwatch_signal_knife_%d"%rng.randi(),"name":"Cinderwatch Signal Knife","slot":"mainhand","visual":"sword","icon":7,"armor":1,"hp":5+rank,"mana":0,"power":15+rank*2,"max_durability":185.0,"description":"A short basalt-iron blade carried by Eastern beacon patrols."}
        elif rng.randf()<.48:
            marcher_reward={"kind":"material","material":"ore","amount":2 if elite else 1,"name":"Marcher Basalt Iron"}
        else:
            marcher_reward={"kind":"item","id":"amberfield_waybread","stack_key":"item:amberfield_waybread","stackable":true,"quantity":1,"name":"Amberfield Waybread","slot":"consumable","icon":10,"use":"food","buff_name":"Long Road","duration":180.0,"buff_power":3,"health_regen":.22,"stamina_regen":3.4,"heal":17.0,"description":"Dense grain and salt baked for the Dawnway. Double-click to eat."}
        _spawn_world_drop(pos+Vector3(.82,0,-.38),marcher_reward,elite)
    if str(profile.get("zone_id",""))=="skeld_coast" and (elite or rng.randf()<.16):
        var coastal_reward:Dictionary
        if elite and rng.randf()<.24:
            coastal_reward={"kind":"item","id":"skeld_raider_guard_%d"%rng.randi(),"name":"Skeld Breakwater Guard","slot":"offhand","visual":"shield","icon":9,"armor":12+rank,"hp":18+rank*2,"mana":0,"power":4+rank,"max_durability":195.0,"description":"A compact saltsteel-and-oak shield recovered on the Grey Sea road."}
        elif rng.randf()<.48:
            coastal_reward={"kind":"material","material":"resin","amount":2 if elite else 1,"name":"Coastal Net Pitch"}
        else:
            coastal_reward={"kind":"item","id":"skeld_smoked_fish","stack_key":"item:skeld_smoked_fish","stackable":true,"quantity":1,"name":"Skeld Smoked Fish","slot":"consumable","icon":10,"use":"food","buff_name":"Sea Legs","duration":180.0,"buff_power":3,"health_regen":.24,"stamina_regen":3.2,"heal":18.0,"description":"Juniper-smoked coastal fish. Double-click to eat."}
        _spawn_world_drop(pos+Vector3(.82,0,-.38),coastal_reward,elite)


func _spawn_zombie_loot(pos:Vector3,kind:String,elite:bool)->void:
    var champion:=kind=="zombie_champion"
    var carrier:=kind=="zombie_carrier"
    var guard:=kind=="zombie_graveguard"
    _spawn_world_drop(pos,{"kind":"material","material":"grave_tokens","amount":6 if champion else (2 if guard else 1),"name":"Grave Tokens"},elite or champion)
    _spawn_world_drop(pos+Vector3(.54,0,.24),{"kind":"gold","amount":65 if champion else (10 if elite else rng.randi_range(2,5)),"name":"Gravebound Coin Pouch"},elite or champion)
    if carrier:
        _spawn_world_drop(pos+Vector3(-.50,0,.18),{"kind":"material","material":"plague_samples","amount":2,"name":"Plague Samples"},true)
    if champion:
        _spawn_world_drop(pos+Vector3(0,0,.72),{"kind":"material","material":"crystal","amount":2,"name":"Graveglass Crystals"},true)
        _spawn_world_drop(pos+Vector3(-.74,0,-.18),{"kind":"item","id":"champion_bone_greaves","name":"Champion's Bone Greaves","slot":"feet","icon":4,"armor":12,"hp":16,"power":5,"description":"Heavy burial greaves taken from the Gravebound Champion."},true)
    elif guard and rng.randf()<.34:
        _spawn_world_drop(pos+Vector3(-.52,0,.20),{"kind":"item","id":"burial_iron_buckler_%d"%rng.randi(),"name":"Burial Iron Buckler","slot":"offhand","visual":"shield","icon":9,"armor":9,"hp":10,"power":2,"description":"A scarred shield carried by a Barrowfen graveguard."},true)
    elif rng.randf()<.18:
        _spawn_world_drop(pos+Vector3(-.44,0,.18),{"kind":"item","id":"gravebound_salve","stack_key":"item:gravebound_salve","stackable":true,"quantity":1,"name":"Gravebound Salve","slot":"consumable","icon":10,"use":"food","buff_name":"Graveward","duration":75.0,"buff_power":2,"health_regen":.22,"stamina_regen":1.2,"heal":14.0,"description":"A sealed battlefield remedy. Double-click to restore health and gain a short graveward buff."},false)


func _spawn_world_drop(pos:Vector3,reward:Dictionary,rare:bool=false)->void:
    var kind:String=reward.get("kind","material")
    var material_name:String=reward.get("material","")
    var grounded_log:=material_name=="logs"
    var root:=Node3D.new();root.name="Dropped_%s"%reward.get("name","Item").replace(" ","_");add_child(root)
    root.global_position=_ground(pos)+Vector3.UP*(.16 if grounded_log else .22)
    root.rotation.y=rng.randf_range(-PI,PI) if grounded_log else 0.0
    var color:=Color(.46,.92,.34)
    if reward.get("kind","")=="gold":color=Color(1.0,.66,.10)
    elif reward.get("kind","")=="item":color=Color(.28,.52,1.0) if not rare else Color(.78,.28,1.0)
    elif reward.get("material","") in ["ore","stone"]:color=Color(.48,.52,.58)
    elif reward.get("material","")=="logs":color=Color(.38,.20,.07)
    elif reward.get("material","")=="crystal":color=Color(.26,.82,1.0)
    var item_id:String=reward.get("id","")
    var scene:PackedScene
    var custom_visual:=false
    if str(reward.get("slot","")).begins_with("ring_"):
        _add_magic_ring_drop_visual(root,reward);custom_visual=true
    elif kind=="gold":scene=COIN_POUCH_SCENE
    elif item_id=="raw_fish":scene=FISH_SCENE
    elif item_id.begins_with("cooked_fish"):scene=COOKED_FISH_SCENE
    elif item_id.begins_with("berries"):scene=BERRIES_SCENE
    elif material_name=="logs":scene=LOG_SCENE
    elif material_name=="raw_meat":scene=VENISON_SCENE
    elif material_name=="chitin":scene=RIME_CHITIN_DROP_SCENE
    elif material_name=="crystal" or material_name=="essence":scene=CRYSTAL_DROP_SCENE
    elif material_name in ["grave_tokens","plague_samples"]:scene=CRYSTAL_DROP_SCENE if material_name=="plague_samples" else COIN_POUCH_SCENE
    elif material_name in ["ore","stone","scrap"]:scene=ORE_DROP_SCENE
    elif kind=="item" and reward.get("slot","")=="mainhand":
        scene=AXE_SCENE if "axe" in item_id.to_lower() else (FISHING_POLE_SCENE if "fishing" in item_id.to_lower() else SWORD_DROP_SCENE)
    elif kind=="item" and reward.get("slot","")=="offhand":scene=SHIELD_DROP_SCENE
    elif kind=="item":scene=ARMOR_DROP_SCENE
    elif material_name in ["herbs","mushrooms","resin"]:scene=BERRIES_SCENE
    else:scene=ORE_DROP_SCENE
    if scene and not custom_visual:
        var authored:=scene.instantiate() as Node3D;authored.name="BlenderPickup";authored.scale=Vector3.ONE*(.72 if material_name=="logs" else .82);root.add_child(authored)
    if not grounded_log:
        var marker:=Label3D.new();marker.text="E - PICK UP\n%s"%str(reward.get("name","Item")).to_upper();marker.position=Vector3(0,.85,0);marker.font_size=24;marker.pixel_size=.009;marker.modulate=Color(1,.86,.45) if rare else Color(.86,.95,.78);marker.outline_size=6;marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED;root.add_child(marker)
    _set_geometry_range(root,170.0)
    # Every drop now rests where it landed. The former bob-and-spin loop made
    # weapons, food and ore read as arcade pickups instead of physical loot.
    loot.append({"node":root,"reward":reward.duplicate(true),"phase":0.0,"floor_y":root.global_position.y,"grounded":true})


func _add_magic_ring_drop_visual(root:Node3D,reward:Dictionary)->void:
    var effect:=str(reward.get("effect","windstep"))
    var color:=Color(.42,.78,1.0) if effect=="frostward" else (Color(1.0,.29,.055) if effect=="emberpulse" else Color(.50,1.0,.68))
    var metal:=_service_material(Color(.72,.73,.70)).duplicate() as StandardMaterial3D
    metal.metallic=.72;metal.roughness=.25
    var gem:=_service_material(color).duplicate() as StandardMaterial3D
    gem.emission_enabled=true;gem.emission=color;gem.emission_energy_multiplier=2.6;gem.roughness=.18
    var band:=MeshInstance3D.new();var torus:=TorusMesh.new();torus.inner_radius=.17;torus.outer_radius=.29;torus.rings=16;torus.ring_segments=10;band.mesh=torus;band.rotation.x=PI*.5;band.position.y=.12;band.material_override=metal;root.add_child(band)
    var stone:=MeshInstance3D.new()
    if str(reward.get("ring_design",""))=="split_band":
        var prism:=BoxMesh.new();prism.size=Vector3(.22,.18,.16);stone.mesh=prism;stone.rotation=Vector3(.12,.40,.18)
    else:
        var crystal_mesh:=SphereMesh.new();crystal_mesh.radius=.13;crystal_mesh.height=.22;crystal_mesh.radial_segments=8;crystal_mesh.rings=5;stone.mesh=crystal_mesh
    stone.position=Vector3(0,.37,0);stone.material_override=gem;root.add_child(stone)
    var glow:=OmniLight3D.new();glow.position=Vector3(0,.30,0);glow.light_color=color;glow.light_energy=.42;glow.omni_range=2.8;glow.shadow_enabled=false;root.add_child(glow)

func _tick_loot(delta: float) -> void:
    for i in range(loot.size()-1,-1,-1):
        var item:=loot[i]
        if not is_instance_valid(item.node): loot.remove_at(i); continue
        if item.get("grounded",false):continue
        item.phase += delta*2.2; item.node.rotation.y += delta*.85; item.node.global_position.y=float(item.get("floor_y",item.node.global_position.y))+.35+sin(item.phase)*.10
        # Drops remain where they landed. They are collected only with E.


func _collect_nearby_loot()->void:
    if _nearby_loot.is_empty():return
    var target:Node=_nearby_loot.get("node")
    for i in range(loot.size()-1,-1,-1):
        if loot[i].get("node")!=target:continue
        _collect_reward(loot[i].get("reward",{}))
        if is_instance_valid(target):target.queue_free()
        loot.remove_at(i)
        break
    _nearby_loot={}


func _collect_reward(reward:Dictionary)->void:
    match reward.get("kind","material"):
        "gold":player.hero_gold+=int(reward.get("amount",1))
        "material":
            var material_kind:String=reward.get("material","scrap")
            var amount:int=int(reward.get("amount",1));player.add_material(material_kind,amount)
            if material_kind in _gathered_counts:_gathered_counts[material_kind]=int(_gathered_counts[material_kind])+amount
        "item":
            var item:=reward.duplicate(true)
            if str(item.get("id","")).is_empty():item["id"]="drop_%d"%rng.randi()
            item.erase("kind");player.add_bag_item(item)
    _notify("Picked up %s"%reward.get("name","item"),Color(.82,1.0,.52))
    _check_quest_rewards()

func _save_game() -> void:
    var data := {"position":[player.global_position.x,player.global_position.y,player.global_position.z],"class":player.active_class,"level":player.hero_level,"xp":player.hero_xp,"next_xp":player.next_xp,"hp":player.hp,"max_hp":player.max_hp,"mana":player.mana,"max_mana":player.max_mana,"gold":player.hero_gold,"shards":player.relic_shards,"hp_potions":player.health_potions,"mp_potions":player.mana_potions,"herbs":player.herbs,"scrap":player.scrap,"ore":player.ore,"essence":player.essence,"logs":player.logs,"leather":player.leather,"cloth":player.cloth,"stone":player.stone,"resin":player.resin,"mushrooms":player.mushrooms,"crystal":player.crystal,"chitin":player.chitin,"raw_meat":player.raw_meat,"grave_tokens":player.grave_tokens,"plague_samples":player.plague_samples,"kills":player.enemies_defeated,"elites":player.elites_defeated,"quest_complete":quest_complete,"quest_goal":quest_goal,"quest_claimed":_quest_claimed,"quest_baselines":_quest_baselines,"gathered_counts":_gathered_counts,"skill_levels":skill_levels,"skill_xp":skill_xp,"bag":player.bag_slots,"equipment_slots":player.equipment_slots,"gravebound_campaign":_gravebound_campaign.get_save_state() if is_instance_valid(_gravebound_campaign) else {},"oathbound_campaign":_oathbound_campaign.get_save_state() if is_instance_valid(_oathbound_campaign) else {}}
    var file:=FileAccess.open("user://broken_knight_save.json",FileAccess.WRITE)
    if file: file.store_string(JSON.stringify(data))

func _load_game() -> void:
    if not FileAccess.file_exists("user://broken_knight_save.json"): return
    var file:=FileAccess.open("user://broken_knight_save.json",FileAccess.READ); var data=JSON.parse_string(file.get_as_text())
    if not data is Dictionary: return
    var p:Array=data.get("position",[0,0,0]); player.global_position=_ground(Vector3(p[0],p[1],p[2]))
    player.hero_level=data.get("level",1); player.hero_xp=data.get("xp",0); player.next_xp=data.get("next_xp",25); player.hero_gold=data.get("gold",4); player.relic_shards=data.get("shards",0); player.health_potions=data.get("hp_potions",2); player.mana_potions=data.get("mp_potions",1); player.herbs=data.get("herbs",0); player.scrap=data.get("scrap",0); player.ore=data.get("ore",0); player.essence=data.get("essence",0); player.enemies_defeated=data.get("kills",0); player.elites_defeated=data.get("elites",0); quest_complete=data.get("quest_complete",false)
    for material_kind in ["logs","leather","cloth","stone","resin","mushrooms","crystal","chitin","raw_meat","grave_tokens","plague_samples"]:player.set(material_kind,int(data.get(material_kind,0)))
    if player.has_method("sync_material_inventory"):player.sync_material_inventory()
    _quest_claimed=data.get("quest_claimed",{})
    _gathered_counts.merge(data.get("gathered_counts",{}),true)
    if data.has("quest_baselines"):
        _quest_baselines=data.get("quest_baselines",{}).duplicate(true)
    else:
        # Old saves counted progress globally. Preserve any currently active
        # chapter, while future chapters will receive a fresh baseline when
        # their prerequisite is completed.
        _quest_baselines={"road_imps":0}
        for quest in QUESTS:
            var requirement:=str(quest.get("requires",""))
            if requirement.is_empty() or bool(_quest_claimed.get(requirement,false)):
                _quest_baselines[str(quest.id)]=0
    quest_goal=maxi(1,int(data.get("quest_goal",quest_goal)))
    var loaded_levels:Array=data.get("skill_levels",skill_levels);var loaded_xp:Array=data.get("skill_xp",skill_xp)
    for i in range(4):skill_levels[i]=maxi(1,int(loaded_levels[i] if i<loaded_levels.size() else 1));skill_xp[i]=maxi(0,int(loaded_xp[i] if i<loaded_xp.size() else 0))
    player.bag_slots=data.get("bag",[])
    player.equipment_slots=data.get("equipment_slots",player.equipment_slots)
    if player.has_method("migrate_equipment_schema"):player.migrate_equipment_schema()
    player.active_class=data.get("class","Warrior" if player.equipment_slots.get("mainhand",{}).get("id","")=="royal_vanguard_sword" else "Mage")
    player.hero_title="Royal Vanguard Warrior" if player.active_class=="Warrior" else "Royal Vanguard Mage"
    if not player.equipment_slots.has("offhand"):
        player.equipment_slots["offhand"]={}
    if not player.equipment_slots.has("mainhand"):
        player.equipment_slots["mainhand"]={}
    if not player.equipment_slots.has("pants"):
        player.equipment_slots["pants"]={}
    player.give_royal_staff()
    player.give_travel_torch()
    player.give_royal_warrior_weapons()
    player.give_starter_axe()
    player.give_starter_pickaxe()
    player.give_starter_fishing_pole()
    player._refresh_equipment_stats()
    player.hp=minf(player.max_hp,data.get("hp",player.max_hp)); player.mana=minf(player.max_mana,data.get("mana",player.max_mana))
    if is_instance_valid(_gravebound_campaign):_gravebound_campaign.load_save_state(data.get("gravebound_campaign",{}))
    if is_instance_valid(_oathbound_campaign):_oathbound_campaign.load_save_state(data.get("oathbound_campaign",{}))


func get_lore_entries()->Array[Dictionary]:
    if is_instance_valid(_oathbound_campaign) and _oathbound_campaign.has_method("get_lore_entries"):
        return _oathbound_campaign.get_lore_entries()
    return []
