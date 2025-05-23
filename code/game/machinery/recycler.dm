#define SAFETY_COOLDOWN 100
#define SOUND_COOLDOWN (0.5 SECONDS)

/obj/machinery/recycler
	name = "recycler"
	desc = "A large crushing machine used to recycle small items inefficiently. There are lights on the side."
	icon = 'icons/obj/recycling.dmi'
	icon_state = "grinder-o0"
	layer = MOB_LAYER+1 // Overhead
	anchored = TRUE
	density = TRUE
	damage_deflection = 15
	var/emergency_mode = FALSE // Temporarily stops machine if it detects a mob
	var/icon_name = "grinder-o"
	var/blood = FALSE
	var/eat_dir = WEST
	var/amount_produced = 1
	var/crush_damage = 1000
	var/eat_victim_items = TRUE
	var/item_recycle_sound = 'sound/machines/recycler.ogg'
	/// For admin fun, var edit always_gib to TRUE (1)
	var/always_gib = FALSE
	/// The last time we played a consumption sound.
	var/last_consumption_sound

/obj/machinery/recycler/Initialize(mapload)
	. = ..()
	AddComponent(/datum/component/material_container, list(MAT_METAL, MAT_GLASS, MAT_PLASMA, MAT_SILVER, MAT_GOLD, MAT_DIAMOND, MAT_URANIUM, MAT_BANANIUM, MAT_TRANQUILLITE, MAT_TITANIUM, MAT_PLASTIC, MAT_BLUESPACE), 0, TRUE, null, null, null, TRUE)
	component_parts = list()
	component_parts += new /obj/item/circuitboard/recycler(null)
	component_parts += new /obj/item/stock_parts/matter_bin(null)
	component_parts += new /obj/item/stock_parts/manipulator(null)
	RefreshParts()
	update_icon(UPDATE_ICON_STATE)

/obj/machinery/recycler/RefreshParts()
	var/amt_made = 0
	var/mat_mod = 0
	for(var/obj/item/stock_parts/matter_bin/B in component_parts)
		mat_mod = 2 * B.rating
	mat_mod *= 50000
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		amt_made = 25 * M.rating //% of materials salvaged
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	materials.max_amount = mat_mod
	amount_produced = min(100, amt_made)

/obj/machinery/recycler/examine(mob/user)
	. = ..()
	. += "<span class='notice'>The power light is [(stat & NOPOWER) ? "<b>off</b>" : "<b>on</b>"]."
	. += "The operation light is [emergency_mode ? "<b>off</b>. [src] has detected a forbidden object with its sensors, and has shut down temporarily." : "<b>on</b>. [src] is active."]"
	if(HAS_TRAIT(src, TRAIT_CMAGGED))
		. += "The safety sensor light is <font color=red>R</font><font color=green>G</font><font color=blue>B</font>.</span>"
	else
		. += "The safety sensor light is [emagged ? "<b>off</b>!" : "<b>on</b>."]</span>"
	. += "The recycler current accepts items from [dir2text(eat_dir)]."

/obj/machinery/recycler/power_change()
	if(!..())
		return
	update_icon(UPDATE_ICON_STATE)

/obj/machinery/recycler/crowbar_act(mob/user, obj/item/I)
	if(default_deconstruction_crowbar(user, I))
		return TRUE

/obj/machinery/recycler/screwdriver_act(mob/user, obj/item/I)
	. = TRUE
	if(!I.use_tool(src, user, 0, volume = I.tool_volume))
		return
	panel_open = !panel_open
	update_icon(UPDATE_OVERLAYS)

/obj/machinery/recycler/update_overlays()
	. = ..()
	if(panel_open)
		. += "grinder-oOpen"

/obj/machinery/recycler/wrench_act(mob/user, obj/item/I)
	if(default_unfasten_wrench(user, I, time = 6 SECONDS))
		return TRUE

/obj/machinery/recycler/cmag_act(mob/user)
	if(emagged)
		to_chat(user, "<span class='warning'>The board is completely fried.</span>")
		return FALSE
	if(!HAS_TRAIT(src, TRAIT_CMAGGED))
		ADD_TRAIT(src, TRAIT_CMAGGED, CLOWN_EMAG)
		if(emergency_mode)
			emergency_mode = FALSE
			update_icon(UPDATE_ICON_STATE)
		playsound(src, "sparks", 75, TRUE, SHORT_RANGE_SOUND_EXTRARANGE)
		to_chat(user, "<span class='notice'>You use the jestographic sequencer on [src].</span>")
		return TRUE

/obj/machinery/recycler/emag_act(mob/user)
	if(HAS_TRAIT(src, TRAIT_CMAGGED))
		to_chat(user, "<span class='warning'>The access panel is coated in yellow ooze...</span>")
		return FALSE
	if(!emagged)
		emagged = TRUE
		if(emergency_mode)
			emergency_mode = FALSE
			update_icon(UPDATE_ICON_STATE)
		playsound(src, "sparks", 75, TRUE, SHORT_RANGE_SOUND_EXTRARANGE)
		to_chat(user, "<span class='notice'>You use the cryptographic sequencer on [src].</span>")
		return TRUE

/obj/machinery/recycler/update_icon_state()
	var/is_powered = !(stat & (BROKEN|NOPOWER))
	if(emergency_mode)
		is_powered = FALSE
	icon_state = icon_name + "[is_powered]" + "[(blood ? "bld" : "")]" // add the blood tag at the end

// This is purely for admin possession !FUN!.
/obj/machinery/recycler/Bump(atom/movable/AM)
	..()
	if(AM)
		Bumped(AM)

/obj/machinery/recycler/Bumped(atom/movable/AM)

	if(stat & (BROKEN|NOPOWER))
		return
	if(!anchored)
		return
	if(emergency_mode)
		return

	var/move_dir = get_dir(loc, AM.loc)
	if(move_dir == eat_dir)
		eat(AM)

/obj/machinery/recycler/proc/eat(atom/AM0, sound = 1)
	var/list/to_eat = list(AM0)
	if(isitem(AM0))
		to_eat += AM0.GetAllContents()
	var/items_recycled = 0

	for(var/i in to_eat)
		var/atom/movable/AM = i
		if(QDELETED(AM))
			continue
		else if(isliving(AM))
			if(emagged)
				crush_living(AM)
			else if(HAS_TRAIT(src, TRAIT_CMAGGED))
				bananafication(AM)
			else
				emergency_stop(AM)
		else if(isitem(AM))
			recycle_item(AM)
			items_recycled++
		else
			playsound(loc, 'sound/machines/buzz-sigh.ogg', 50, 0)
			AM.forceMove(loc)

	if(items_recycled && sound && (last_consumption_sound + SOUND_COOLDOWN) < world.time)
		playsound(loc, item_recycle_sound, 100, 0)
		last_consumption_sound = world.time

/obj/machinery/recycler/proc/recycle_item(obj/item/I)
	I.forceMove(loc)

	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	var/material_amount = materials.get_item_material_amount(I)
	if(!material_amount)
		qdel(I)
		return
	materials.insert_item(I, multiplier = (amount_produced / 100))
	qdel(I)
	materials.retrieve_all()


/obj/machinery/recycler/proc/emergency_stop(mob/living/L)
	playsound(loc, 'sound/machines/buzz-sigh.ogg', 50, 0)
	emergency_mode = TRUE
	update_icon(UPDATE_ICON_STATE)
	L.loc = loc
	addtimer(CALLBACK(src, PROC_REF(reboot)), SAFETY_COOLDOWN)

/obj/machinery/recycler/proc/reboot()
	playsound(loc, 'sound/machines/ping.ogg', 50, 0)
	emergency_mode = FALSE
	update_icon(UPDATE_ICON_STATE)

/obj/machinery/recycler/proc/bananafication(mob/living/L)
	L.loc = loc
	if(!iscarbon(L))
		playsound(loc, 'sound/machines/buzz-sigh.ogg', 50, 0)
		return
	var/mob/living/carbon/human/victim = L
	playsound(src, 'sound/items/AirHorn.ogg', 100, TRUE, -1)
	victim.bananatouched_harmless()

/obj/machinery/recycler/proc/crush_living(mob/living/L)

	L.loc = loc

	if(issilicon(L))
		playsound(loc, 'sound/items/welder.ogg', 50, 1)
	else
		playsound(loc, 'sound/effects/splat.ogg', 50, 1)

	var/gib = TRUE
	// By default, the emagged recycler will gib all non-carbons. (human simple animal mobs don't count)
	if(iscarbon(L))
		gib = FALSE
		if(L.stat == CONSCIOUS)
			L.say("ARRRRRRRRRRRGH!!!")
		add_mob_blood(L)

	if(!blood && !issilicon(L))
		blood = TRUE
		update_icon(UPDATE_ICON_STATE)

	// Remove and recycle the equipped items
	if(eat_victim_items)
		for(var/obj/item/I in L.get_equipped_items(TRUE))
			if(L.drop_item_to_ground(I))
				eat(I, sound = 0)

	// Instantly lie down, also go unconscious from the pain, before you die.
	L.Paralyse(10 SECONDS)

	if(gib || always_gib)
		L.gib()
	else if(emagged)
		L.adjustBruteLoss(crush_damage)


/obj/machinery/recycler/AltClick(mob/user)
	if(user.stat || HAS_TRAIT(user, TRAIT_HANDS_BLOCKED) || !Adjacent(user))
		return

	eat_dir = turn(eat_dir, 90)
	to_chat(user, "<span class='notice'>[src] will now accept items from [dir2text(eat_dir)].</span>")

/obj/machinery/recycler/deathtrap
	name = "dangerous old crusher"
	emagged = TRUE
	crush_damage = 120


/obj/item/paper/recycler
	name = "paper - 'garbage duty instructions'"
	info = "<h2>New Assignment</h2> You have been assigned to collect garbage from trash bins, located around the station. The crewmembers will put their trash into it and you will collect the said trash.<br><br>There is a recycling machine near your closet, inside maintenance; use it to recycle the trash for a small chance to get useful minerals. Then deliver these minerals to cargo or engineering. You are our last hope for a clean station, do not screw this up!"

#undef SOUND_COOLDOWN

#undef SAFETY_COOLDOWN
