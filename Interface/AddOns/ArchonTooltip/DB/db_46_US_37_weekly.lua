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

local lookup = {'Druid-Balance','Druid-Restoration','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Discipline','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Druid-Guardian','DemonHunter-Devourer','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Mage-Fire','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','Rogue-Assassination','Paladin-Holy','DemonHunter-Vengeance','Shaman-Enhancement','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Aconite:BAAALgAECgUJBQAAAA==.',
Ad='Adhoria:BAAALgAECgEJAgAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8kAAMBAAYJIx72EwBOAQABAAUJCB/2EwBOAQACAAQJIBqKHQBMAQAuAAQKfzAAAwEACQmOI5QQAJsCAAEACAmRJJQQAJsCAAIACQmgHU8jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8wAAIDAAkJOyNEAwByAwADAAkJOyNEAwByAwAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgAECgIJAgAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1QIwCjAQAEAAgJzA1QIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn8yAAIGAAkJERUJCgARAgAGAAkJERUJCgARAgAAAA==.Alkaline:BAAALgADCgQJBAAAAA==.Altheyra:BAAALgAECgYJBgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn82AAIHAAkJ6g7jUADRAQAHAAkJ6g7jUADRAQAAAA==.Amelía:BAAALgAECgYJBgABLgAFFAQJEwACAMoJAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8TAAMCAAQJygnCLwDjAAACAAQJygnCLwDjAAABAAIJwwLOFwB5AAAuAAQKfyEAAwIACQn1F4soAPsBAAIACQn1F4soAPsBAAEAAQlOHfZwAE0AAAAA.',
An='Angando:BAABLgAECn8mAAIIAAkJWxPFEADFAQAIAAkJWxPFEADFAQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAABLgAECn8ZAAIBAAgJShBYKwBfAQABAAgJShBYKwBfAQAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Ariellá:BAAALgAECgEJAQAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8vAAQJAAkJTyCIBQDAAgAJAAkJfB+IBQDAAgAKAAYJGiEVIQA/AgALAAEJngr/igAwAAAAAA==.Artishard:BAAALgADCgMJAwAAAA==.',
As='Ashkaari:BAACLgAFFH8QAAIMAAQJQQ15NgDqAAAMAAQJQQ15NgDqAAAuAAQKfxsAAgwACQnUHFUSAKICAAwACQnUHFUSAKICAAAA.Asuná:BAABLgAECn8fAAMNAAkJchFPGADuAQANAAkJJhBPGADuAQAOAAYJVQoVRwAdAQAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgUJCgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgIJAgABLgAFFAYJJAABACMeAA==.',
Ba='Backerrz:BAACLgAFFH8gAAIPAAYJHxG5JwB5AQAPAAYJHxG5JwB5AQAuAAQKfzAAAw8ACQlPHG4XAIsCAA8ACQlPHG4XAIsCABAAAwlAGS45ANAAAAAA.Bamberk:BAAALgADCgMJAwABLgAECgcJIAAPAHEeAA==.',
Be='Bearbrownie:BAAALgAECgEJAQAAAA==.Bearwidit:BAAALgAECgYJCQAAAA==.Beefbrownie:BAABLgAECn8jAAIIAAkJjSP2AQAmAwAIAAkJjSP2AQAmAwAAAA==.Bellezora:BAAALgAECgUJBQABLgAECgkJIAACAFcTAA==.Berz:BAAALgAECgYJCwAAAA==.Berzerked:BAACLgAFFH8IAAIRAAQJOByrDABSAQARAAQJOByrDABSAQAuAAQKfy8AAhEACQltI6wBACcDABEACQltI6wBACcDAAAA.Bestboygrip:BAAALgAECgcJEgAAAA==.Betelgues:BAAALgAECgEJAQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAABLgAECn8WAAMDAAcJKhqYLQCaAQADAAcJKhqYLQCaAQASAAYJiAcESwDBAAAAAA==.Bigsave:BAABLgAECn8cAAICAAkJCA+CTABJAQACAAkJCA+CTABJAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blindem:BAAALgADCgEJAQABLgAECgkJJgACAA8lAA==.Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8WAAITAAQJ8xlhEwAlAQATAAQJ8xlhEwAlAQAuAAQKf0MAAhMACQldINYHAIgCABMACQldINYHAIgCAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn8sAAMDAAkJdBR4HwD3AQADAAkJdBR4HwD3AQAUAAEJ1xbNfQBEAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgYJDwAAAA==.',
Bu='Buckett:BAAALgAECgMJAwAAAA==.Buckfuttz:BAAALgAECggJDgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH81AAISAAYJmiVMAACAAgASAAYJmiVMAACAAgAuAAQKfxcAAhIACQlfJngAANkDABIACQlfJngAANkDAAEuAAUUCQkcABUA/yMA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAABLgAECn8kAAIIAAgJxxX/EQC0AQAIAAgJxxX/EQC0AQAAAA==.',
Ch='Chainmalejr:BAAALgAECgYJBgABLgAFFAQJFAAHADcYAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAAALgAECgcJDgAAAA==.Chiyukii:BAAALgAECgkJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKgAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8oAAIKAAkJrxzYIABMAgAKAAkJrxzYIABMAgAAAA==.Cowmein:BAABLgAECn8XAAMBAAcJSQyhPgD4AAABAAcJSQyhPgD4AAACAAEJ4AQj4AAkAAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAABLgAECn8aAAIWAAcJ9RkrPwC0AQAWAAcJ9RkrPwC0AQAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAYJJwAXAKwbAA==.',
Da='Dameian:BAAALgAECgEJAQAAAA==.Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAABLgAECn8fAAISAAkJ+A4yHwCaAQASAAkJ+A4yHwCaAQAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAQJFAAHADcYAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.Deäthknight:BAAALgAECgEJAQAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8UAAIYAAQJbBpOFgBDAQAYAAQJbBpOFgBDAQAuAAQKfyEAAhgACQnXGQwaAAkCABgACQnXGQwaAAkCAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgYJCQAAAA==.',
Do='Donald:BAABLgAECn9IAAMBAAkJDhb0FQAJAgABAAkJDhb0FQAJAgACAAMJiwdCpwB5AAAAAA==.Doublea:BAAALgAECggJEwAAAA==.',
Dr='Dragonchest:BAAALgAECgUJCAAAAA==.Dragonswolf:BAABLgAECn8uAAIYAAgJtRU6JQC4AQAYAAgJtRU6JQC4AQAAAA==.Dragonwing:BAAALgAECgEJAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgYJBwAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAYJJAADAEclAA==.Dregon:BAACLgAFFH8kAAIDAAYJRyXeBACHAgADAAYJRyXeBACHAgAuAAQKfy0AAwMACQkwJmACAGYDAAMACQkwJmACAGYDABQAAgnlIalaAKUAAAAA.Dreinara:BAAALgAECgYJDgAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Duff:BAAALgADCggJCQAAAA==.Dummysezwhut:BAABLgAECn8kAAIBAAgJehBBKAB0AQABAAgJehBBKAB0AQAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn85AAIZAAgJ1RPHVACzAQAZAAgJ1RPHVACzAQAAAA==.',
El='Elena:BAAALgAECgIJAgABLgAECgkJMAADADsjAA==.Elesis:BAAALgADCgQJBAAAAA==.Ellida:BAABLgAECn8aAAIXAAcJMxGQIwC7AQAXAAcJMxGQIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJEAAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8iAAMQAAkJPR6LAwBAAgAQAAgJIB+LAwBAAgAPAAgJBhrUPADbAQAAAA==.',
Fa='Fangmage:BAABLgAECn8UAAMaAAcJbQ+cBgAhAQAaAAYJhRCcBgAhAQAHAAYJ2whuxwDfAAAAAA==.Fayker:BAAALgAECggJDAAAAA==.Fazlain:BAABLgAECn8jAAIKAAgJLB4CJwAtAgAKAAgJLB4CJwAtAgAAAA==.',
Fe='Felestis:BAAALgAECgYJCQAAAA==.Felnir:BAAALgAECgMJBAABLgAECgkJGQAPALsJAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAQJEwANAGcSAA==.',
Fl='Fluffydragon:BAACLgAFFH8KAAIbAAMJNhxkGAD0AAAbAAMJNhxkGAD0AAAuAAQKfyYAAxsACQkkHJwEAMkCABsACQkkHJwEAMkCABwABQnnB2QoAN0AAAAA.',
Fr='Friartuck:BAAALgAECgcJCQABLgAFFAMJCAAKACIdAA==.Frosteez:BAAALgAECgEJAQABLgAECgYJEwAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8mAAMCAAkJDyVnAQDAAwACAAkJDyVnAQDAAwAdAAMJGyL3FwAtAQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8zAAIBAAkJix3tCACyAgABAAkJix3tCACyAgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAACLgAFFH8IAAIZAAMJlhI7VgDgAAAZAAMJlhI7VgDgAAAuAAQKfzgAAhkACAkdGUdOAMQBABkACAkdGUdOAMQBAAAA.Gatelinka:BAAALgAECgcJEQABLgAFFAMJCgAbADYcAA==.Gateto:BAABLgAECn8qAAMMAAgJ1yDnCQDaAgAMAAgJ1yDnCQDaAgAeAAQJiBD6VADKAAABLgAFFAMJCgAbADYcAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Gn='Gnomechomsky:BAAALgADCggJDAAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJDgAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgAECgUJCAAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Healthat:BAAALgAECgEJAgAAAA==.Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8pAAIQAAkJ1hTBBQD0AQAQAAkJ1hTBBQD0AQAAAA==.Helsreach:BAAALgADCgcJBwAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hrungnir:BAAALgAECgQJBgAAAA==.Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAABLgAECn8YAAMKAAYJ1RfedAA9AQAKAAYJNBfedAA9AQALAAQJsw3cXQDKAAAAAA==.Huntinbub:BAABLgAECn81AAMKAAgJGREYTgCfAQAKAAgJGREYTgCfAQALAAEJzQAxmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgkJBAAAAA==.',
In='Instaque:BAAALgAECgQJBAAAAA==.',
Ir='Irim:BAAALgAECgQJBAAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECggJDwABLgAFFAQJFAAYAGwaAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8WAAIWAAUJahdcNgAmAQAWAAUJahdcNgAmAQAuAAQKfyQAAxYACAmYIeARAPACABYACAmYIeARAPACAB8AAglECPthAFoAAAAA.Izlaar:BAAALgADCgkJIAAAAA==.Izzytt:BAAALgAECgUJCQAAAA==.',
Ja='Jacenskie:BAABLgAECn8jAAIYAAkJbBJJLQCJAQAYAAkJbBJJLQCJAQAAAA==.Jacob:BAAALgAECgQJCgAAAA==.Jadedbabe:BAAALgAECgUJBwAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgAECgYJBwABLgAFFAQJFAAHADcYAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAFFAcJGgAXALAaAA==.Joyvimon:BAAALgAECgYJDwAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIgAAgJdwtkhABFAQAgAAgJdwtkhABFAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJyxunFQB6AQAEAAYJyxunFQB6AQAcAAIJEgemBgClAAAuAAQKfxUAAxwACQkBIL4OAO8BAAQABwmCGvgXABMCABwABgnGI74OAO8BAAAA.Khornedaemon:BAAALgAECgQJBQAAAA==.',
Ki='Kickstarter:BAAALgAFFAIJAwAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgAECggJEAAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAABLgAECn8WAAIPAAgJHgPSvQDBAAAPAAgJHgPSvQDBAAAAAA==.Kronas:BAAALgAECgcJDAAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIWAAkJfxu3PAABAgAWAAkJfxu3PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8TAAQNAAQJZxJPIAAVAQANAAQJ0g9PIAAVAQAOAAIJVhSpDACZAAAXAAIJfADkNgAzAAAuAAQKfx8ABA4ACQl+G7oLAJMCAA4ACQl+G7oLAJMCAA0ABAlUBrE/ALEAABcAAgkgBi5YAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAQJEwANAGcSAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8kAAIOAAYJVBuABgC9AQAOAAYJVBuABgC9AQAuAAQKfzQAAw4ACQnOIKYDAB8DAA4ACQnOIKYDAB8DABcAAwktCwRhAGYAAAAA.Leomoon:BAAALgAECgMJBgAAAA==.Leshy:BAAALgAECgYJDAAAAA==.Levite:BAABLgAECn8eAAMOAAYJqxvEHADIAQAOAAYJqxvEHADIAQANAAUJGhJXNwAPAQAAAA==.',
Li='Lickytung:BAAALgADCgcJBwAAAA==.Lightwork:BAAALgAECgEJAQAAAA==.Lilara:BAABLgAECn8ZAAIPAAgJzAfifgAwAQAPAAgJzAfifgAwAQAAAA==.Linthsong:BAAALgAECgQJBAABLgAECgcJFAAOAF4QAA==.Lionknite:BAACLgAFFH8GAAIgAAQJLAsHZAAWAQAgAAQJLAsHZAAWAQAuAAQKfy0AAiAACQnqGzErAD8CACAACQnqGzErAD8CAAAA.Liontabu:BAAALgAECgQJBgAAAA==.Liorii:BAAALgAECgEJAQAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAQJEwANAGcSAA==.Littledung:BAAALgADCgkJEAAAAA==.',
Lo='Looting:BAABLgAECn8kAAIhAAcJhBV/CQCTAQAhAAcJhBV/CQCTAQAAAA==.',
Lu='Lunexiya:BAABLgAECn8ZAAIWAAkJJgIG0wBmAAAWAAkJJgIG0wBmAAAAAA==.Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAACLgAFFH8JAAICAAMJgwgPPwCmAAACAAMJgwgPPwCmAAAuAAQKfyEAAwIACAnuCwhdADsBAAIACAnuCwhdADsBAB0AAQkoAkZSABwAAAAA.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIKAAgJxQuHagBVAQAKAAgJxQuHagBVAQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAABLgAECn8UAAMZAAQJLhUY6QC0AAAZAAMJGhUY6QC0AAAiAAQJHgt3YACXAAAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Matsumoto:BAAALgAECgEJAgAAAA==.Mauka:BAABLgAECn8pAAMBAAgJTBDdOABUAQABAAYJQBTdOABUAQACAAgJzQsCSgBUAQAAAA==.Mauzer:BAAALgAECgEJAQABLgAECggJMQAfAOgbAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8nAAIgAAkJUh4UMAB3AgAgAAkJUh4UMAB3AgAAAA==.Mclinkdink:BAAALgADCgkJCQAAAA==.Mcscrotie:BAABLgAECn8UAAIgAAgJQgbnogASAQAgAAgJQgbnogASAQAAAA==.',
Me='Mes:BAABLgAECn8jAAIeAAkJghtbGAAIAgAeAAkJghtbGAAIAgAAAA==.Metatrøn:BAAALgADCgEJAQAAAA==.',
Mi='Mimmi:BAAALgAECgUJEQABLgAECggJMQAfAOgbAA==.Mishri:BAACLgAFFH8MAAIWAAQJuiHYHwCDAQAWAAQJuiHYHwCDAQAuAAQKfzQAAhYACQn2JGgDAEEDABYACQn2JGgDAEEDAAAA.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8xAAMfAAgJ6BsPDgAkAgAfAAgJ3RsPDgAkAgAjAAIJ8RkYKwBBAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMZAAYJPwg76QCzAAAZAAYJPwg76QCzAAAGAAQJ0wIuNgBrAAAAAA==.Myodieboy:BAAALgAECgIJAgAAAA==.',
Na='Nakabeam:BAABLgAECn8qAAIWAAkJuBQINgDXAQAWAAkJuBQINgDXAQAAAA==.Nakatwin:BAABLgAECn8YAAIWAAcJJhXmWACXAQAWAAcJJhXmWACXAQABLgAECgkJKgAWALgUAA==.Naklek:BAABLgAECn8hAAMdAAgJBh6TBgCOAgAdAAgJBh6TBgCOAgAVAAEJYgtiNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8TAAIKAAUJFxuHDQDwAAAKAAUJFxuHDQDwAAAuAAQKfyMAAwoACQmtH5sOAMYCAAoACQmtH5sOAMYCAAsABAl0BlRpAJkAAAAA.Nika:BAAALgAECgYJCgAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8oAAMOAAkJmAnYKQBjAQAOAAkJmAnYKQBjAQAXAAEJ0wHeawAaAAAAAA==.',
No='Noriala:BAAALgAECgYJCAABLgAECgkJMwAHAC0kAA==.Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAABLgAECn8ZAAIPAAkJuwn4WQCEAQAPAAkJuwn4WQCEAQAAAA==.',
Or='Orcdung:BAAALgADCgYJBgAAAA==.',
Os='Ostpeppar:BAAALgADCgUJBgAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAABLgAECn8XAAQiAAgJ7xQMMwByAQAiAAcJeRQMMwByAQAGAAgJeA/0HgARAQAZAAEJcwPNmgEgAAAAAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgAECgYJBgABLgAFFAQJFAAYAGwaAA==.Panzerfäust:BAAALgAECgYJEwAAAA==.Pawrina:BAAALgAFFAEJAQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgAECgQJBAAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8uAAMZAAkJwBZLOQAFAgAZAAkJwBZLOQAFAgAiAAQJzgh+XgCfAAAAAA==.Philster:BAAALgAFFAIJAgAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Po='Poochieboo:BAAALgADCgQJBAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAABLgAECn8jAAIOAAkJRRWPFQAQAgAOAAkJRRWPFQAQAgAAAA==.Punchem:BAAALgADCgcJBwABLgAECgkJJgACAA8lAA==.Purex:BAABLgAECn8dAAIhAAkJKQYwCgCSAQAhAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgYJBgAAAA==.Pyria:BAAALgADCgUJBQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ4Bo4DADoAQAGAAgJ4Bo4DADoAQAAAA==.Rathus:BAABLgAECn8gAAIPAAcJcR7ELwBOAgAPAAcJcR7ELwBOAgAAAA==.Rawdata:BAACLgAFFH8MAAMMAAMJwAovSQCtAAAMAAMJwAovSQCtAAAkAAEJFQkcFABEAAAuAAQKfykAAyQACQk5FaEOAKgBACQACQk5FaEOAKgBAAwACAkvD1RCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIKAAgJqRetPQC4AQAKAAgJqRetPQC4AQAAAA==.Rebeka:BAABLgAECn8cAAIiAAgJ2R2zDwCIAgAiAAgJ2R2zDwCIAgABLgAECggJIAAKAKkXAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEQABLgAECgkJHwASAPgOAA==.Reniel:BAAALgAECgIJAgABLgAECgkJMgAGABEVAA==.Ressie:BAAALgAECgQJCQAAAA==.Reston:BAAALgAECgYJBgABLgAECggJIQAlAHMjAA==.Reverendlion:BAABLgAECn8WAAIXAAgJ7BYCHQC/AQAXAAgJ7BYCHQC/AQAAAA==.',
Ri='Riyu:BAAALgADCgEJAgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAFFAMJBAABLgAFFAUJFwAZALITAA==.',
Sa='Saiko:BAAALgAECgMJAwABLgAFFAQJEQAPANIHAA==.Sainthealz:BAAALgAECgEJAQAAAA==.Saladcake:BAABLgAECn8gAAIHAAgJzBJhYgChAQAHAAgJzBJhYgChAQAAAA==.Salleane:BAACLgAFFH8FAAIZAAIJQQ9nfACMAAAZAAIJQQ9nfACMAAAuAAQKfxgAAhkACAm2FTNeAMkBABkACAm2FTNeAMkBAAAA.Samgompers:BAAALgADCgIJAgAAAA==.Sampal:BAABLgAECn84AAMGAAkJoBt7BwBOAgAGAAgJjx57BwBOAgAZAAEJFAeBeQEvAAAAAA==.Sampriest:BAABLgAECn8jAAMOAAgJXSCOCADNAgAOAAgJXSCOCADNAgANAAEJpxAzaQA0AAABLgAECgkJOAAGAKAbAA==.Samwield:BAACLgAFFH8ZAAImAAUJDiJjEABjAQAmAAUJDiJjEABjAQAuAAQKfzwABCYACQnHITgFAM8CACYACQnHITgFAM8CACEAAwlCGEsTAM0AACcAAQnUCtsgAC8AAAAA.Sanchoe:BAAALgAECggJEAAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.Saucemoe:BAAALgAECgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn80AAMMAAkJpRs/EQCtAgAMAAkJpRs/EQCtAgAeAAEJIAbXpQAiAAAAAA==.Selaheal:BAABLgAECn82AAIXAAkJmBc6EQAxAgAXAAkJmBc6EQAxAgAAAA==.Seraath:BAACLgAFFH8hAAIjAAYJXxhcAgBiAQAjAAYJXxhcAgBiAQAuAAQKfyYAAyMACQn3IZAAAGQDACMACQn3IZAAAGQDABYAAQkAAJDSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadowskull:BAAALgADCgkJFQAAAA==.Shadwkllr:BAAALgAECgYJEwAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAABLgAECn8WAAIQAAYJQiDlBgDQAQAQAAYJQiDlBgDQAQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Si='Sinister:BAAALgAFFAMJAwAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skid:BAAALgADCgEJAQAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Sneakyhoof:BAAALgADCgcJBwAAAA==.Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgAECgYJDgAAAA==.',
St='Stabbem:BAAALgADCgEJAQABLgAECgkJJgACAA8lAA==.Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBQAAAA==.Stersèbuk:BAAALgADCgMJAwABLgAFFAIJAgAFAAAAAA==.Stervana:BAACLgAFFH8IAAIEAAQJjxpmIQAjAQAEAAQJjxpmIQAjAQAuAAQKfy0AAgQACQl0IOIDAFoDAAQACQl0IOIDAFoDAAEuAAUUAgkCAAUAAAAA.Sterzephyr:BAAALgAFFAIJAgAAAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8sAAMbAAkJ3g5TFAByAQAbAAkJ3g5TFAByAQAcAAcJOwuuEQDcAAAAAA==.',
Su='Sundemonhunt:BAAALgAECgMJAwAAAA==.Sunnmonk:BAAALgADCgQJBAAAAA==.Sunpally:BAAALgAECgMJBAAAAA==.Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8KAAIHAAMJmxJkLwD5AAAHAAMJmxJkLwD5AAABLgAFFAYJIwAIANMkAA==.Suswar:BAACLgAFFH8jAAIIAAYJ0ySdAwD/AQAIAAYJ0ySdAwD/AQAuAAQKfzAAAggACQnIJJoAALgDAAgACQnIJJoAALgDAAAA.Suvulaan:BAABLgAECn83AAMbAAgJdwfJGAA0AQAbAAgJdwfJGAA0AQAEAAYJkgPdYwCGAAAAAA==.',
Sw='Swifix:BAAALgAECgYJBgAAAA==.Swordsmyth:BAAALgADCgEJAQAAAA==.',
Ta='Tacostand:BAACLgAFFH8aAAIWAAYJKhWDIgB1AQAWAAYJKhWDIgB1AQAuAAQKfzIAAhYACQlNIOUHAEwDABYACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAACLgAFFH8IAAIKAAMJIh0HQAAMAQAKAAMJIh0HQAAMAQAuAAQKfzwAAgoACQnII3oEADoDAAoACQnII3oEADoDAAAA.',
Te='Teeice:BAABLgAECn8iAAIhAAkJdRMWBgD8AQAhAAkJdRMWBgD8AQAAAA==.Teo:BAABLgAECn8jAAIXAAkJmxPbGQDaAQAXAAkJmxPbGQDaAQAAAA==.Terian:BAAALgAECgkJBwAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIeAAkJAhErMwBUAQAeAAkJAhErMwBUAQAAAA==.Thekan:BAABLgAECn8bAAIfAAkJlhQ2EwDcAQAfAAkJlhQ2EwDcAQAAAA==.Theriot:BAACLgAFFH8GAAMZAAMJuRDdVgDfAAAZAAMJuRDdVgDfAAAGAAIJmAJVEgBNAAAuAAQKfy0ABBkACQmaGzk8APsBABkACQmaGzk8APsBAAYABgkIDHMlAM4AACIAAQkzCEegACgAAAAA.Thianá:BAABLgAECn8VAAIMAAcJxwuwWAA1AQAMAAcJxwuwWAA1AQAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tiermoghuen:BAAALgAECgEJAQAAAA==.Tikidragoona:BAAALgAECgIJAgAAAA==.Timberdoodle:BAAALgAECgMJAwAAAA==.Timtamslam:BAAALgAECgYJCwAAAA==.Tinkerspell:BAABLgAECn8gAAICAAkJVxOrKwDoAQACAAkJVxOrKwDoAQAAAA==.Tinkiebella:BAAALgAECgEJAgABLgAECgkJIAACAFcTAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
Tl='Tlitlitzin:BAAALgAECgMJAwAAAA==.',
To='Tobivoker:BAAALgAECgQJBQAAAA==.Toosus:BAABLgAFFH8PAAITAAQJVSF0GQDwAAATAAQJVSF0GQDwAAABLgAFFAYJIwAIANMkAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIkAAQJYQcsCQAEAQAkAAQJYQcsCQAEAQAuAAQKfxoAAiQACAkrFG0KACoCACQACAkrFG0KACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJBAAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgkJCgAAAA==.',
Tr='Treatimus:BAAALgADCgMJAwABLgAECgkJOAAXAAchAA==.Treesum:BAAALgADCgQJBAAAAA==.Trolldung:BAAALgAECgEJAQAAAA==.Truffaut:BAAALgAECgEJAQAAAA==.',
Tt='Tturtle:BAACLgAFFH8RAAIZAAQJGAo2RQAJAQAZAAQJGAo2RQAJAQAuAAQKfyUAAhkACQl+Fd8wAF8CABkACQl+Fd8wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJCwAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAAALgAECgcJDwABLgAFFAUJGQAmAA4iAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vecna:BAAALgAECgMJAwABLgAECgYJCAAFAAAAAA==.Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8cAAIHAAUJWw+FzgDUAAAHAAUJWw+FzgDUAAAAAA==.Velvethunda:BAAALgAECgYJBgAAAA==.Verdugo:BAAALgAECgUJDwAAAA==.Verite:BAABLgAECn8bAAMgAAcJzQNv+gCUAAAgAAcJxwJv+gCUAAAoAAMJOgUEFABTAAAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8jAAIYAAkJ9Rt5EABiAgAYAAkJ9Rt5EABiAgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgAECgEJAgAAAA==.Voidedge:BAABLgAECn8lAAMQAAcJxQ8FGgDAAAAPAAcJjQ0YdgBxAQAQAAUJBxEFGgDAAAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
Vy='Vynivar:BAAALgADCgEJAQAAAA==.Vynlan:BAAALgAECgQJBAABLgAFFAYJJAADAEclAA==.',
We='Wes:BAABLgAECn84AAIhAAkJvRoHAwB7AgAhAAkJvRoHAwB7AgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAcJHQAgAN0iAA==.Willybwankin:BAACLgAFFH8dAAIgAAcJ3SKbAABrAgAgAAcJ3SKbAABrAgAuAAQKfykAAiAACQkxJsoAAOEDACAACQkxJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAABLgAECn8VAAIGAAkJsgv3IQD4AAAGAAkJsgv3IQD4AAAAAA==.',
Wy='Wyvern:BAABLgAECn8gAAIPAAkJFA6PSQCyAQAPAAkJFA6PSQCyAQAAAA==.',
Xa='Xanthion:BAAALgAECgUJCAAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAAALgAECggJEgAAAA==.Zalarian:BAAALgAECgYJBwABLgAECgkJSAAHAEkgAA==.Zalmage:BAABLgAECn9IAAMHAAkJSSCgEQDdAgAHAAkJSSCgEQDdAgApAAIJ5wlqFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgYJCAAAAA==.Zeseroth:BAACLgAFFH8fAAIZAAYJwCCjDwCtAQAZAAYJwCCjDwCtAQAuAAQKfycAAhkACQmkIywDAKMDABkACQmkIywDAKMDAAAA.Zeserotho:BAAALgAFFAEJAQAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIOAAQJ1SRoCQCIAQAOAAQJ1SRoCQCIAQAuAAQKfyUAAw4ACQndIBEGAO4CAA4ACQndIBEGAO4CABcABAllE3ZjAF8AAAAA.',
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
