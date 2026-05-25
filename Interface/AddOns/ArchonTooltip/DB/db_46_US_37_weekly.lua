local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Druid-Balance','Druid-Restoration','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','DemonHunter-Devourer','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8jAAMBAAYJIx6UEABcAQABAAUJCB+UEABcAQACAAQJIBo+GgBPAQAuAAQKfzAAAwEACQmOI5QQAJsCAAEACAmRJJQQAJsCAAIACQmgHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8qAAIDAAgJiiQvBQAsAwADAAgJiiQvBQAsAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgADCgUJBAAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn8sAAIGAAgJwBSZDQC8AQAGAAgJwBSZDQC8AQAAAA==.Alkaline:BAAALgADCgQJBAAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn8wAAIHAAkJ+gxmUgDIAQAHAAkJ+gxmUgDIAQAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMCAAQJyglpKgDuAAACAAQJyglpKgDuAAABAAIJwwLOFwB5AAAuAAQKfyEAAwIACQn1FwwmAPwBAAIACQn1FwwmAPwBAAEAAQlOHepoAE4AAAAA.',
An='Angando:BAABLgAECn8jAAIIAAgJxBNREwCQAQAIAAgJxBNREwCQAQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8ZAAIBAAgJShDQJwBgAQABAAgJShDQJwBgAQAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8rAAQJAAgJDCC/CwBMAgAJAAgJGx+/CwBMAgAKAAYJGiEVIQA/AgALAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8QAAIMAAQJQQ2ILgDyAAAMAAQJQQ2ILgDyAAAuAAQKfxUAAgwACQl3FmInAPQBAAwACQl3FmInAPQBAAAA.Asuná:BAABLgAECn8WAAMNAAkJmA90OAD+AAAOAAYJVQoVRwAdAQANAAQJtxR0OAD+AAAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgQJBAAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAYJIwABACMeAA==.',
Ba='Backerrz:BAACLgAFFH8fAAIPAAYJQQ63IgB1AQAPAAYJQQ63IgB1AQAuAAQKfzAAAw8ACQlPHJsUAJICAA8ACQlPHJsUAJICABAAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJIAAPAHEeAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8bAAIIAAkJMCPDAgD6AgAIAAkJMCPDAgD6AgAAAA==.Bellezora:BAAALgAECgUJBQABLgAECggJHQACALwTAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAABLgAECn8vAAIRAAkJbSOsAQAnAwARAAkJbSOsAQAnAwAAAA==.Bestboygrip:BAAALgAECgYJDgAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAABLgAECn8WAAMDAAcJKhppKACaAQADAAcJKhppKACaAQASAAYJiAcIRwDDAAAAAA==.Bigsave:BAABLgAECn8cAAICAAkJCA8CSABMAQACAAkJCA8CSABMAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJHwACAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8WAAITAAQJ8xm2DwAzAQATAAQJ8xm2DwAzAQAuAAQKf0MAAhMACQldIMYGAI8CABMACQldIMYGAI8CAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn8mAAMDAAkJGBIJJAC4AQADAAkJGBIJJAC4AQAUAAEJYAhGiQAsAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgYJDgAAAA==.',
Bu='Buckett:BAAALgAECgMJAwAAAA==.Buckfuttz:BAAALgAECgcJCgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH8vAAISAAYJmiVMAACAAgASAAYJmiVMAACAAgAuAAQKfxcAAhIACQlfJngAANkDABIACQlfJngAANkDAAEuAAUUCQkXABUAnyMA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn8jAAIIAAgJkhV7EAC4AQAIAAgJkhV7EAC4AQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJFAAHADcYAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAAALgAECgcJBwAAAA==.Chiyukii:BAAALgAECgEJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJGgAIAFYdAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8lAAIKAAgJiBo3OwDHAQAKAAgJiBo3OwDHAQAAAA==.Cowmein:BAABLgAECn8XAAMBAAcJSQwQOgD4AAABAAcJSQwQOgD4AAACAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIWAAcJ9RkROgC9AQAWAAcJ9RkROgC9AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAUJIAAXAAofAA==.',
Da='Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAABLgAECn8aAAISAAcJPQ7eMQAcAQASAAcJPQ7eMQAcAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJFAAHADcYAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8UAAIYAAQJbBpLEQBMAQAYAAQJbBpLEQBMAQAuAAQKfyEAAhgACQnXGf4WABICABgACQnXGf4WABICAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgQJCQAAAA==.',
Do='Donald:BAABLgAECn9AAAMBAAkJTBVaFQD+AQABAAkJTBVaFQD+AQACAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECggJEwAAAA==.',
Dr='Dragonchest:BAAALgAECgMJAwAAAA==.Dragonswolf:BAABLgAECn8uAAIYAAgJtRW1IQC+AQAYAAgJtRW1IQC+AQAAAA==.Dragonwing:BAAALgAECgEJAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgUJBwAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAYJIwADADUlAA==.Dregon:BAACLgAFFH8jAAIDAAYJNSU8AwCQAgADAAYJNSU8AwCQAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABQAAgnlIalaAKUAAAAA.Dreinara:BAAALgAECgUJDgAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8jAAIBAAgJfBAWJQB0AQABAAgJfBAWJQB0AQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn8yAAIZAAgJDxF6ZACHAQAZAAgJDxF6ZACHAQAAAA==.',
El='Elena:BAAALgAECgIJAgABLgAECggJKgADAIokAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIXAAcJMxGQIwC7AQAXAAcJMxGQIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJDQAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMQAAkJPR4PAwBIAgAQAAgJIB8PAwBIAgAPAAgJBhpaOADfAQAAAA==.',
Fa='Fangmage:BAAALgAECgcJDQAAAA==.Fayker:BAAALgAECggJDAAAAA==.Fazlain:BAABLgAECn8jAAIKAAgJLB4qIgAyAgAKAAgJLB4qIgAyAgAAAA==.',
Fe='Felestis:BAAALgAECgYJCAAAAA==.Felnir:BAAALgAECgEJAQABLgAECggJFwAPACUKAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAQJEwANAGcSAA==.',
Fl='Fluffydragon:BAACLgAFFH8HAAIaAAMJaBUhGADfAAAaAAMJaBUhGADfAAAuAAQKfyYAAxoACQkkHCEEANECABoACQkkHCEEANECABsABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAAALgAECgcJCQABLgAFFAIJBQAKAJUZAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8fAAMCAAkJDyU5AQDAAwACAAkJDyU5AQDAAwAcAAEJXhihNgBHAAAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8wAAIBAAkJDR1+CACpAgABAAkJDR1+CACpAgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8FAAIZAAMJHQ69TwDjAAAZAAMJHQ69TwDjAAAuAAQKfzMAAhkACAkdGSRQALkBABkACAkdGSRQALkBAAAA.Gatelinka:BAAALgAECgcJDQABLgAFFAMJBwAaAGgVAA==.Gateto:BAABLgAECn8oAAMMAAgJ1yDnCQDaAgAMAAgJ1yDnCQDaAgAdAAQJiBDETgDLAAABLgAFFAMJBwAaAGgVAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gn='Gnomechomsky:BAAALgADCgcJBwAAAA==.',
Go='Goobull:BAAALgADCgEJAQAAAA==.Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJCgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Healthat:BAAALgAECgEJAQAAAA==.Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8mAAIQAAgJjxXZBgC8AQAQAAgJjxXZBgC8AQAAAA==.Helsreach:BAAALgADCgMJAgAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hrungnir:BAAALgAECgIJAgAAAA==.Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMKAAYJ1RcgagBAAQAKAAYJNBcgagBAAQALAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn8vAAMKAAgJGRHXRgCgAQAKAAgJGRHXRgCgAQALAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
Ir='Irim:BAAALgAECgQJBAAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJDwABLgAFFAQJFAAYAGwaAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8VAAIWAAUJaheILQAyAQAWAAUJaheILQAyAQAuAAQKfyQAAxYACAmYIeARAPACABYACAmYIeARAPACAB4AAglECPthAFoAAAAA.Izlaar:BAAALgADCgkJIAAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIYAAkJbBKzKACSAQAYAAkJbBKzKACSAQAAAA==.Jacob:BAAALgAECgQJCQAAAA==.Jadedbabe:BAAALgAECgUJBwAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJFAAHADcYAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAFFAcJGgAXALAaAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIfAAgJdwu4egBIAQAfAAgJdwu4egBIAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxvtEACJAQAEAAYJyxvtEACJAQAbAAIJEgemBgClAAAuAAQKfxUAAxsACQkBIL4OAO8BAAQABwmCGvgXABMCABsABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBAAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgAECggJDgAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAAALgAECggJEAAAAA==.Kronas:BAAALgAECgcJCwAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIWAAkJfxu3PAABAgAWAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8TAAQNAAQJZxK2GwAsAQANAAQJ0g+2GwAsAQAOAAIJVhSpDACZAAAXAAIJfACXMAA8AAAuAAQKfx8ABA4ACQl+G1sKAJwCAA4ACQl+G1sKAJwCAA0ABAlUBrE/ALEAABcAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAQJEwANAGcSAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8jAAIOAAYJVBvlBADMAQAOAAYJVBvlBADMAQAuAAQKfzQAAw4ACQnOIKYDAB8DAA4ACQnOIKYDAB8DABcAAwktC6BbAGgAAAAA.Leomoon:BAAALgAECgMJBAAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMOAAYJqxtTGgDPAQAOAAYJqxtTGgDPAQANAAUJGhLVMgAeAQAAAA==.',
Li='Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIPAAgJzAfIdgA2AQAPAAgJzAfIdgA2AQAAAA==.Lionknite:BAABLgAECn8sAAIfAAkJhxspKQA6AgAfAAkJhxspKQA6AgAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAQJEwANAGcSAA==.Littledung:BAAALgADCgkJEAAAAA==.',
Lo='Looting:BAABLgAECn8dAAIgAAcJxBJFCgBxAQAgAAcJxBJFCgBxAQAAAA==.',
Lu='Lunexiya:BAAALgAECgkJCQAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8GAAICAAMJgwh7OACxAAACAAMJgwh7OACxAAAuAAQKfyAAAwIACAl2CwhdADsBAAIACAl2CwhdADsBABwAAQkoAr1IAB0AAAAA.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIKAAgJxQsbYgBUAQAKAAgJxQsbYgBUAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMZAAQJLhWI1wDDAAAZAAMJGhWI1wDDAAAhAAQJHgt5WwCXAAAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Mauka:BAABLgAECn8hAAMBAAgJTBDdOABUAQABAAYJQBTdOABUAQACAAgJwws4RgBTAQAAAA==.Mauzer:BAAALgAECgEJAQABLgAECggJLQAeAOQYAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIfAAkJUh4UMAB3AgAfAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIfAAgJQgahlgAUAQAfAAgJQgahlgAUAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIdAAkJghv9FQALAgAdAAkJghv9FQALAgAAAA==.Metatrøn:BAAALgADCgEJAQAAAA==.',
Mi='Mimmi:BAAALgAECgUJEAABLgAECggJLQAeAOQYAA==.Mishri:BAACLgAFFH8LAAIWAAQJuiFBGQCNAQAWAAQJuiFBGQCNAQAuAAQKfzIAAhYACQnQJEgDAEMDABYACQnQJEgDAEMDAAAA.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8tAAMeAAgJ5BhWEADuAQAeAAgJ2RhWEADuAQAiAAIJ8RniJwBBAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMZAAYJPwhj0wDJAAAZAAYJPwhj0wDJAAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgADCgEJAgAAAA==.',
Na='Nakabeam:BAABLgAECn8qAAIWAAkJuBRWMQDhAQAWAAkJuBRWMQDhAQAAAA==.Nakatwin:BAABLgAECn8YAAIWAAcJJhXmWACXAQAWAAcJJhXmWACXAQABLgAECgkJKgAWALgUAA==.Naklek:BAABLgAECn8hAAMcAAgJBh6TBgCOAgAcAAgJBh6TBgCOAgAVAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8SAAIKAAUJFxuHDQDwAAAKAAUJFxuHDQDwAAAuAAQKfyMAAwoACQmtH5sOAMYCAAoACQmtH5sOAMYCAAsABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCQAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8lAAMOAAgJ+giWLQA6AQAOAAgJ+giWLQA6AQAXAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgEJAQABLgAECggJMQAHAMEjAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAABLgAECn8XAAIPAAgJJQoTaQBUAQAPAAgJJQoTaQBUAQAAAA==.',
Or='Orcdung:BAAALgADCgYJBgAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8WAAMhAAgJbhKJLwB0AQAhAAcJeRSJLwB0AQAGAAgJeA/0HgARAQAAAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgADCgkJCQABLgAFFAQJFAAYAGwaAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAECgkJEQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8rAAMZAAgJKxa8TQDAAQAZAAgJKxa8TQDAAQAhAAQJzgidWQCfAAAAAA==.Philster:BAAALgAECgMJAwAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8WAAIOAAgJbRW3GgDMAQAOAAgJbRW3GgDMAQAAAA==.Punchem:BAAALgADCgcJBwAAAA==.Purex:BAABLgAECn8dAAIgAAkJKQYwCgCSAQAgAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgUJBQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ4Br/CgDsAQAGAAgJ4Br/CgDsAQAAAA==.Rathus:BAABLgAECn8gAAIPAAcJcR7ELwBOAgAPAAcJcR7ELwBOAgAAAA==.Rawdata:BAACLgAFFH8KAAIMAAMJuQrOPgC2AAAMAAMJuQrOPgC2AAAuAAQKfykAAyMACQk5FQYNAKsBACMACQk5FQYNAKsBAAwACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIKAAgJqRetPQC4AQAKAAgJqRetPQC4AQAAAA==.Rebeka:BAABLgAECn8cAAIhAAgJ2R0bDgCNAgAhAAgJ2R0bDgCNAgABLgAECggJIAAKAKkXAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgcJGgASAD0OAA==.Reniel:BAAALgADCgYJBgABLgAECggJLAAGAMAUAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAECggJIQAkAHMjAA==.Reverendlion:BAABLgAECn8UAAIXAAgJtxXtGwC/AQAXAAgJtxXtGwC/AQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAFFAEJAQABLgAFFAQJEgAZABkTAA==.',
Sa='Saiko:BAAALgAECgMJAwABLgAFFAQJEQAPANIHAA==.Sainthealz:BAAALgAECgEJAQAAAA==.Saladcake:BAABLgAECn8fAAIHAAgJzBLrWwCuAQAHAAgJzBLrWwCuAQAAAA==.Salleane:BAABLgAECn8YAAIZAAgJthUzXgDJAQAZAAgJthUzXgDJAQAAAA==.Sampal:BAABLgAECn8yAAMGAAkJjRuCBwA3AgAGAAgJeh6CBwA3AgAZAAEJFAdTYwExAAAAAA==.Sampriest:BAABLgAECn8jAAMOAAgJXSBaBwDWAgAOAAgJXSBaBwDWAgANAAEJpxC2YAA3AAABLgAECgkJMgAGAI0bAA==.Samwield:BAACLgAFFH8VAAIlAAUJDiIIDQBvAQAlAAUJDiIIDQBvAQAuAAQKfzwABCUACQnHIW0EANgCACUACQnHIW0EANgCACAAAwlCGEsTAM0AACYAAQnUCukdAC8AAAAA.Sanchoe:BAAALgAECgcJDgAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn8uAAMMAAkJoBt6DwCtAgAMAAkJoBt6DwCtAgAdAAEJIAbWmAAiAAAAAA==.Selaheal:BAABLgAECn8wAAIXAAkJPhafFQD6AQAXAAkJPhafFQD6AQAAAA==.Seraath:BAACLgAFFH8hAAIiAAYJXxjQAQBoAQAiAAYJXxjQAQBoAQAuAAQKfyYAAyIACQn3IZAAAGQDACIACQn3IZAAAGQDABYAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadowskull:BAAALgADCgkJFQAAAA==.Shadwkllr:BAAALgAECgUJEgAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8VAAIQAAYJQiANBgDUAQAQAAYJQiANBgDUAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAAALgAECgUJBQAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJHwACAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stergertha:BAAALgAECgEJAQABLgAFFAQJCAAEAI8aAA==.Stervana:BAACLgAFFH8IAAIEAAQJjxryGwAwAQAEAAQJjxryGwAwAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAAA.Sterzephyr:BAAALgAFFAIJAgABLgAFFAQJCAAEAI8aAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8sAAMaAAkJ3g7WEgB4AQAaAAkJ3g7WEgB4AQAbAAcJOwt2EADfAAAAAA==.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAECgIJAgAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIHAAMJmxJkLwD5AAAHAAMJmxJkLwD5AAABLgAFFAYJIgAIANMkAA==.Suswar:BAACLgAFFH8iAAIIAAYJ0yR3AgASAgAIAAYJ0yR3AgASAgAuAAQKfzAAAggACQnIJJoAALgDAAgACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn8xAAMaAAgJdwd2FwA0AQAaAAgJdwd2FwA0AQAEAAUJcwPMXwCLAAAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.',
Ta='Tacostand:BAACLgAFFH8aAAIWAAYJKhXQGwB/AQAWAAYJKhXQGwB/AQAuAAQKfzIAAhYACQlNIOUHAEwDABYACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAACLgAFFH8FAAIKAAIJlRkWUQC0AAAKAAIJlRkWUQC0AAAuAAQKfzcAAgoACQnIIwYEADYDAAoACQnIIwYEADYDAAAA.',
Te='Teeice:BAABLgAECn8iAAIgAAkJdRNmBQAEAgAgAAkJdRNmBQAEAgAAAA==.Teo:BAABLgAECn8gAAIXAAgJURIsIACdAQAXAAgJURIsIACdAQAAAA==.Terian:BAAALgAECgkJBwAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIdAAkJAhFALwBWAQAdAAkJAhFALwBWAQAAAA==.Thekan:BAABLgAECn8bAAIeAAkJlhQQEQDjAQAeAAkJlhQQEQDjAQAAAA==.Theriot:BAACLgAFFH8GAAMZAAMJuRCGSwDrAAAZAAMJuRCGSwDrAAAGAAIJmAIQEABNAAAuAAQKfy0ABBkACQmaG/EzABACABkACQmaG/EzABACAAYABgkIDIsiAM8AACEAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8UAAIMAAcJewkeXAARAQAMAAcJewkeXAARAQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgEJAQAAAA==.Tikidragoona:BAAALgAECgIJAgAAAA==.Timtamslam:BAAALgAECgYJBwAAAA==.Tinkerspell:BAABLgAECn8dAAICAAgJvBPqNACkAQACAAgJvBPqNACkAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECggJHQACALwTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAITAAQJVSHCFQD6AAATAAQJVSHCFQD6AAABLgAFFAYJIgAIANMkAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIjAAQJYQdLBwALAQAjAAQJYQdLBwALAQAuAAQKfxoAAiMACAkrFG0KACoCACMACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJAwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgUJCgAAAA==.',
Tr='Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAAALgADCgkJEQAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8QAAIZAAQJGArKOQAXAQAZAAQJGArKOQAXAQAuAAQKfyUAAhkACQl+Fd8wAF8CABkACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJCwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAAALgAECgcJDgABLgAFFAUJFQAlAA4iAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8cAAIHAAUJWw+EwQDqAAAHAAUJWw+EwQDqAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJCwAAAA==.Verite:BAABLgAECn8bAAMfAAcJzQMe6QCUAAAfAAcJxwIe6QCUAAAnAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIYAAkJ9RvwDQBtAgAYAAkJ9RvwDQBtAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgAECgEJAQAAAA==.Voidedge:BAABLgAECn8lAAMQAAcJxQ/cFwDEAAAPAAcJjQ0YdgBxAQAQAAUJBxHcFwDEAAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vy='Vynlan:BAAALgAECgQJBAABLgAFFAYJIwADADUlAA==.',
We='Wes:BAABLgAECn84AAIgAAkJvRqZAgCFAgAgAAkJvRqZAgCFAgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAcJHAAfAN0iAA==.Willybwankin:BAACLgAFFH8cAAIfAAcJ3SKbAABrAgAfAAcJ3SKbAABrAgAuAAQKfykAAh8ACQkxJsoAAOEDAB8ACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8UAAIGAAgJIAz3IQD4AAAGAAgJIAz3IQD4AAAAAA==.',
Wy='Wyvern:BAABLgAECn8YAAIPAAgJkgzLYABoAQAPAAgJkgzLYABoAQAAAA==.',
Xa='Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAAALgAECgYJDAAAAA==.Zalarian:BAAALgAECgYJBwABLgAECgkJPwAHAF4eAA==.Zalmage:BAABLgAECn8/AAMHAAkJXh6dFgC3AgAHAAkJXh6dFgC3AgAoAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgYJCAAAAA==.Zeseroth:BAACLgAFFH8fAAIZAAYJwCAOCgDFAQAZAAYJwCAOCgDFAQAuAAQKfycAAhkACQmkIywDAKMDABkACQmkIywDAKMDAAAA.Zeserotho:BAAALgAECgQJBgAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIOAAQJ1STSBwCTAQAOAAQJ1STSBwCTAQAuAAQKfyUAAw4ACQndIBEGAO4CAA4ACQndIBEGAO4CABcABAllEyleAGAAAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
