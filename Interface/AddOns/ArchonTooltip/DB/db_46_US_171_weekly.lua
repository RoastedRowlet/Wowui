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

local lookup = {'Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Rogue-Subtlety','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','Druid-Guardian','Evoker-Preservation','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Evoker-Augmentation','Monk-Windwalker','Shaman-Elemental','Druid-Balance','DemonHunter-Vengeance','Paladin-Holy','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','DemonHunter-Devourer','Priest-Shadow','DeathKnight-Frost','Hunter-Survival','Warlock-Demonology',}
local provider = {region='US',realm='Onyxia',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abrams:BAABLgAECn8XAAIBAAgJyBhTOwDPAQABAAgJyBhTOwDPAQAAAA==.',
Ad='Addý:BAABLgAECn8XAAICAAkJfxe9HQARAgACAAkJfxe9HQARAgAAAA==.Advanced:BAAALgADCgQJAQAAAA==.',
Ah='Ahimsa:BAABLgAECn8uAAIDAAkJHRyOAwAAAgADAAkJHRyOAwAAAgAAAA==.',
Al='Alisonchains:BAABLgAECn8fAAIEAAYJCyQ2EQDPAQAEAAYJCyQ2EQDPAQAAAA==.Alkyri:BAAALgAECgEJAQAAAA==.Alternate:BAABLgAECn8rAAIFAAkJThZULAAnAgAFAAkJThZULAAnAgAAAA==.',
Am='Amigo:BAAALgADCgEJAQAAAA==.Amillerbrew:BAABLgAECn8aAAIGAAgJTxaYJQDXAQAGAAgJTxaYJQDXAQAAAA==.',
An='Anayanci:BAAALgAECgQJDAAAAA==.Anesh:BAAALgAECgMJBQAAAA==.Anjuna:BAAALgAECgYJDwAAAA==.Anshee:BAAALgAECgIJAwAAAA==.Anubrin:BAAALgADCgUJBwAAAA==.',
As='Ashenclaw:BAABLgAECn8kAAIHAAgJ+heeBADmAQAHAAgJ+heeBADmAQAAAA==.',
Au='Auzatryx:BAAALgAECgYJCgAAAA==.',
Ba='Bamboom:BAAALgAECgUJEQAAAA==.Bapbap:BAAALgADCgYJBgAAAA==.',
Be='Beefstick:BAAALgAECgMJAgAAAA==.Belanik:BAAALgAECgEJAwAAAA==.Beleth:BAAALgADCgYJBgAAAA==.',
Bi='Bigblktotem:BAABLgAECn8WAAMIAAYJlAzwFwBDAQAIAAYJlAzwFwBDAQAJAAMJHQSegwBdAAABLgAFFAMJCgAKALEYAA==.Biggrnmonstr:BAAALgAECgYJDAABLgAFFAMJCgAKALEYAA==.Bigrabit:BAAALgADCgMJBAAAAA==.Biirf:BAAALgAECgUJBgAAAA==.',
Bl='Blãze:BAAALgADCgIJAgAAAA==.',
Bo='Bogdan:BAAALgADCgEJAQAAAA==.Bomi:BAAALgAECgQJCQAAAA==.Boogiebm:BAAALgAECgcJCwAAAA==.Borgon:BAAALgAECgEJAgAAAA==.Bowevil:BAAALgADCgMJAwAAAA==.Boypartz:BAABLgAECn8rAAMLAAgJoh0NCQAMAgALAAgJoh0NCQAMAgAMAAEJKwmNTQAiAAAAAA==.',
Br='Breakfast:BAAALgAECgEJAQAAAA==.',
Bu='Bulbasaurus:BAACLgAFFH8OAAINAAQJpiStBACgAQANAAQJpiStBACgAQAuAAQKfx8AAg0ACQmjIkoEAOsCAA0ACQmjIkoEAOsCAAAA.Bulloney:BAAALgADCgIJAgAAAA==.Bunana:BAAALgADCgIJAgAAAA==.Bus:BAAALgAFFAMJAwABLgAFFAkJFgAOALEhAA==.',
Ca='Cabooze:BAAALgAECgQJBAAAAA==.Cacho:BAAALgAECgQJCAAAAA==.Cañonazo:BAAALgAECgEJAQAAAA==.',
Ce='Celeres:BAABLgAECn8eAAIPAAgJeBgiEQAqAgAPAAgJeBgiEQAqAgAAAA==.Celys:BAAALgAECgUJBgAAAA==.Cerealkillah:BAAALgAECgEJAQAAAA==.',
Ch='Chantilly:BAAALgAECgEJAQAAAA==.Chartreuse:BAAALgADCgMJBAABLgAECgUJBQAQAAAAAA==.Chaw:BAAALgAECgEJAQAAAA==.Cheesecurds:BAAALgADCgcJBwAAAA==.Cheesied:BAAALgADCgQJAwAAAA==.Chios:BAAALgAECgUJBQABLgAFFAcJFAAMAJ4YAA==.',
Cl='Cleetiscat:BAAALgAECgYJBgAAAA==.',
Co='Cowabunga:BAAALgADCgEJAQAAAA==.',
Cr='Crow:BAAALgAFFAYJEQAAAQ==.Cryoblade:BAAALgADCgcJDAAAAA==.',
Cu='Cuttanee:BAAALgAECggJDAAAAA==.',
Cy='Cyril:BAAALgADCgkJFwAAAA==.',
Da='Daevon:BAAALgAECgQJEAAAAA==.Daron:BAAALgAECgcJDgAAAA==.Darrowreaper:BAABLgAECn8WAAIRAAcJIQ2/bgA/AQARAAcJIQ2/bgA/AQAAAA==.',
De='Deadcell:BAAALgAECgYJBwAAAA==.Deatheria:BAAALgADCgMJAwAAAA==.Denarrage:BAACLgAFFH8GAAISAAQJ4wPjDQCgAAASAAQJ4wPjDQCgAAAuAAQKfy4AAhIACQnsFOAMAPYBABIACQnsFOAMAPYBAAAA.Denawage:BAAALgAECggJCAAAAA==.',
Di='Dirtytotem:BAAALgAECgcJDQAAAA==.Discordia:BAAALgAECggJDQAAAA==.Dizyizy:BAAALgAECgUJBwAAAA==.',
Do='Dontnerfspls:BAAALgAECgMJBQABLgAFFAMJCgAKALEYAA==.Doomby:BAAALgAECgYJBgABLgAECggJJQASAKgXAA==.',
Dr='Drakesh:BAAALgADCgEJAQAAAA==.Drakussy:BAAALgAECgYJDAABLgAECggJJQASAKgXAA==.Drudekay:BAAALgAECgEJAQAAAA==.',
Du='Dullslinkie:BAAALgADCgEJAQAAAA==.',
El='Eldarborn:BAAALgAECgUJBQAAAA==.Eleannar:BAAALgAECgEJAQAAAA==.Elficpaladin:BAAALgAECgYJCQAAAA==.Elixxi:BAAALgAECgQJBQAAAA==.Elladin:BAAALgADCgcJBwAAAA==.Ellipsi:BAAALgAECgUJCAAAAA==.Ellipsoro:BAACLgAFFH8IAAIRAAMJBB4cWACvAAARAAMJBB4cWACvAAAuAAQKfy4AAhEACQl2JRAEAD4DABEACQl2JRAEAD4DAAAA.Eltrol:BAABLgAFFH8FAAITAAMJbgnUOQDhAAATAAMJbgnUOQDhAAAAAA==.Eluriana:BAAALgAECgQJBQABLgAFFAQJDgAGABIRAA==.',
Er='Erale:BAAALgADCgYJDAAAAA==.Eredarn:BAAALgADCgEJAQAAAA==.Erienor:BAAALgADCgkJDAAAAA==.',
Ev='Evldrprkchop:BAAALgADCgIJAgAAAA==.',
Ex='Executiepie:BAACLgAFFH8UAAIMAAcJnhhiAQDbAQAMAAcJnhhiAQDbAQAuAAQKfyIAAgwACQmiILkCADsDAAwACQmiILkCADsDAAAA.',
Fa='Faeris:BAACLgAFFH8IAAMUAAMJFhKAHgDcAAAUAAMJFhKAHgDcAAAVAAEJMQ2qEgBPAAAuAAQKfyIAAxUACQkkItMBAFkDABUACQkkItMBAFkDABQAAgnfGodFAI0AAAAA.Faolain:BAABLgAECn8kAAICAAgJQBE9NwB0AQACAAgJQBE9NwB0AQAAAA==.Fatalis:BAACLgAFFH8RAAITAAUJvwcxKQAZAQATAAUJvwcxKQAZAQAuAAQKfykAAxMACQk9GYUeACICABMACAmkHIUeACICAAMACAlcBLJRAAYBAAAA.',
Fe='Fetch:BAAALgAECgkJBgAAAA==.',
Fi='Fiddlestix:BAAALgAECgUJCgAAAA==.Fims:BAAALgAECgYJCgAAAA==.Finarfin:BAAALgADCgkJCQAAAA==.Fireballcat:BAAALgADCgMJBQAAAA==.Fizaw:BAABLgAECn8uAAIWAAkJXwZFNQALAQAWAAkJXwZFNQALAQAAAA==.',
Fl='Floydbussy:BAABLgAFFH8IAAIXAAUJTgwlIgAGAQAXAAUJTgwlIgAGAQAAAA==.',
Fr='Freeng:BAAALgADCgYJBgAAAA==.Freeze:BAAALgAECgEJAQAAAA==.Frøzen:BAAALgAECgIJAgAAAA==.',
Fu='Fuzzydots:BAAALgAECgMJBgAAAA==.',
['Fë']='Fëanør:BAABLgAECn8XAAIBAAgJ7RO0ZgCzAQABAAgJ7RO0ZgCzAQAAAA==.',
Ga='Galnir:BAAALgAECgMJAwAAAA==.Gatorbait:BAAALgAECgQJBAAAAA==.Gaurr:BAAALgAECgMJBAAAAA==.Gazzcool:BAAALgAECgQJBwAAAA==.',
Ge='Geneviere:BAAALgAECgQJBQAAAA==.Gex:BAAALgAECgYJCgAAAA==.',
Gh='Ghostzen:BAACLgAFFH8IAAIYAAMJXBqgEgDrAAAYAAMJXBqgEgDrAAAuAAQKfx0AAhgACQlUJQgBALsDABgACQlUJQgBALsDAAAA.',
Gi='Gislain:BAABLgAECn8eAAMJAAgJUBHROgCWAQAJAAgJUBHROgCWAQAZAAYJ3Qz+PADpAAAAAA==.',
Go='Goldeye:BAAALgADCgMJAwAAAA==.Gothmogsbane:BAABLgAECn8WAAMCAAgJdRFmRQAyAQACAAYJzRFmRQAyAQAaAAgJLATEUgDcAAAAAA==.',
Gr='Greaves:BAAALgAECgQJBAABLgAFFAQJEgAbAHclAA==.Greyspirit:BAABLgAECn8vAAIOAAkJKSB0AgDTAgAOAAkJKSB0AgDTAgAAAA==.Grez:BAAALgAECgQJBgAAAA==.Grubnub:BAAALgADCgEJAQABLgAECgkJLQAJAJsaAA==.',
Gu='Gumpy:BAAALgAECggJDAAAAA==.',
Ha='Halcoldrek:BAAALgAECgMJAwAAAA==.Hamburguesa:BAAALgAECgEJAQAAAA==.Hanta:BAAALgADCgIJAwAAAA==.Harkiel:BAAALgAECgUJBwAAAA==.',
He='Heyz:BAABLgAECn8jAAMUAAgJKRx3CgB3AgAUAAgJKRx3CgB3AgAVAAEJkwCligAhAAAAAA==.',
Hi='Hibernate:BAAALgADCgIJAgAAAA==.Himbo:BAAALgAECgcJCQAAAA==.Hipocrit:BAAALgAECgcJCQAAAA==.',
Ho='Hog:BAAALgAECgYJBgAAAA==.Holypoopp:BAABLgAECn8zAAMBAAkJnR0vGAB0AgABAAkJnR0vGAB0AgAcAAYJKRR6SgBOAQAAAA==.Hondalorian:BAABLgAECn81AAITAAkJURb/GgA3AgATAAkJURb/GgA3AgAAAA==.Honkmydemon:BAAALgADCgMJAwAAAA==.Honkmyscars:BAAALgAECgEJAQAAAA==.Hordranir:BAAALgADCgIJAgAAAA==.',
['Hë']='Hëxy:BAAALgADCgYJBgAAAA==.',
Im='Imran:BAACLgAFFH8NAAIdAAMJBwuZCACcAAAdAAMJBwuZCACcAAAuAAQKfzUAAx0ACQmhE5sMAKYBAB0ACQmhE5sMAKYBAAEABwmhBKXPAOoAAAAA.',
In='Inkdawarlock:BAAALgAECgEJAQAAAA==.',
['Iå']='Iåomai:BAAALgADCgMJAwAAAA==.',
Ja='Jabronee:BAABLgAECn8YAAINAAYJYBlALABVAQANAAYJYBlALABVAQAAAA==.',
Je='Jerikoh:BAAALgAECgEJAQAAAA==.Jether:BAAALgAECgUJDgAAAA==.',
Jk='Jkingoreborn:BAABLgAECn8bAAIdAAcJ6B8pCAAAAgAdAAcJ6B8pCAAAAgABLgAECggJFwADABYQAA==.',
Jo='Jodormi:BAAALgADCgkJCQABLgAECggJEwAQAAAAAA==.Jodrin:BAAALgADCgEJAQAAAA==.Jojobaggins:BAABLgAECn8aAAQeAAcJPhoDCQBtAQAEAAUJeRdkMQB8AQAeAAcJFhcDCQBtAQAfAAQJLBpTBwAwAQAAAA==.Jopine:BAAALgAECgEJAQABLgAECggJEwAQAAAAAA==.',
Ka='Kaadriluna:BAAALgADCgMJBAAAAA==.Kaena:BAAALgADCgYJBgAAAA==.Kaey:BAAALgAECgQJBAAAAA==.Kaname:BAAALgAECgYJEAAAAA==.Katalyst:BAAALgAECgIJAgAAAA==.',
Ke='Keiri:BAAALgADCgMJAwAAAA==.Keyholes:BAABLgAFFH8LAAIKAAUJ/BwKDAA6AQAKAAUJ/BwKDAA6AQABLgAFFAcJFAAMAJ4YAA==.Keyohs:BAAALgAECgUJBQABLgAFFAcJFAAMAJ4YAA==.',
Kh='Khe:BAAALgAECgYJBwABLgAECgkJLQAJAJsaAA==.',
Ki='Kittybear:BAAALgAFFAEJAQABLgAFFAcJHwAMAO0jAA==.',
Kk='Kkoda:BAAALgAECgUJBQAAAA==.',
Ko='Koal:BAABLgAECn8hAAITAAgJuhhGKgDlAQATAAgJuhhGKgDlAQAAAA==.Kodabear:BAAALgADCgcJBwAAAA==.',
Kp='Kpop:BAAALgADCgcJBwABLgAFFAgJHgADACYiAA==.',
Kr='Kreen:BAAALgADCgcJBwAAAA==.Krom:BAAALgAECgcJEAABLgAECggJIgAJAOQOAA==.Kronos:BAAALgAECgcJBwABLgAECgYJCgAQAAAAAA==.',
Ku='Kushage:BAAALgAECgEJAQAAAA==.',
Ky='Kyomu:BAAALgADCgMJAwAAAA==.',
La='Lara:BAABLgAECn8iAAMTAAgJhw+9QwCAAQATAAgJhw+9QwCAAQADAAYJ/goTSwAmAQAAAA==.Lavaa:BAAALgADCgEJAQAAAA==.',
Le='Leibniz:BAAALgADCgMJAwAAAA==.Lettussy:BAABLgAFFH8MAAQEAAQJGx5CCQBzAQAEAAQJGx5CCQBzAQAfAAQJCgc9BAAVAQAeAAEJRwq3DABLAAABLgAFFAYJEwAFAKMZAA==.Ley:BAAALgAECgUJBQAAAA==.',
Li='Lix:BAAALgAECgUJEwAAAA==.',
Lo='Loliruri:BAAALgAECgYJCgAAAA==.Loreleì:BAAALgADCgMJAwAAAA==.Louis:BAAALgAECgEJAQAAAA==.',
Lu='Luffymd:BAAALgAECgQJBwAAAA==.Luminyssa:BAAALgAECgYJBwAAAA==.',
['Lú']='Lúthien:BAABLgAECn80AAIWAAkJ5iIDBAApAwAWAAkJ5iIDBAApAwAAAA==.',
Ma='Madoka:BAAALgAECgYJCwAAAA==.Makari:BAAALgADCgMJAwAAAA==.Matrix:BAAALgAECgMJAwAAAA==.Mavenn:BAAALgAECgEJAQAAAA==.Maxchungus:BAABLgAECn81AAMRAAkJ8iGzDQDEAgARAAkJ8iGzDQDEAgAKAAYJPQ8WJAAgAQAAAA==.',
Me='Meatsuit:BAAALgAECgIJAgAAAA==.Meloo:BAABLgAECn8lAAMSAAgJqBfCDQDnAQASAAgJqBfCDQDnAQAgAAYJ2AbejwCsAAAAAA==.Meteor:BAAALgADCgUJBQAAAA==.',
Mi='Mightguy:BAAALgAECgEJAQAAAA==.Mikehawncho:BAAALgAECgQJBwABLgAECgcJHgARAFUbAA==.',
Mo='Moknahddon:BAAALgADCgQJBAAAAA==.Moment:BAABLgAECn8dAAIHAAkJMRmfAgBRAgAHAAkJMRmfAgBRAgAAAA==.Morthrisia:BAAALgADCgUJBQAAAA==.',
Mu='Muna:BAAALgAECgEJAQAAAA==.Murrmau:BAAALgAECgYJDgAAAA==.Muufarmer:BAAALgADCggJCAAAAA==.',
Na='Naerys:BAAALgAECgcJDAAAAA==.Nalguilidan:BAAALgADCgYJBgAAAA==.Natmau:BAAALgADCgQJBAAAAA==.Naughtyelf:BAAALgADCgQJBQAAAA==.',
Ne='Nemene:BAAALgADCgEJAQAAAA==.Neyt:BAABLgAECn8hAAMgAAkJKBsNFgBUAgAgAAkJKBsNFgBUAgASAAEJiRURcAA1AAAAAA==.',
Ni='Niddalee:BAAALgAECgYJBgAAAA==.Nioh:BAAALgAECgYJCQAAAA==.Niohscuck:BAAALgADCgEJAQAAAA==.Nitesrider:BAAALgAECgQJCAAAAA==.',
No='Nora:BAACLgAFFH8VAAIBAAcJ+B8uAgDrAQABAAcJ+B8uAgDrAQAuAAQKfzYAAwEACQlvJrsDADoDAAEACQlvJrsDADoDABwAAwkrFlFIAMYAAAAA.Nori:BAAALgADCgkJDgABLgAFFAcJIgAFAKokAA==.Noshikoshi:BAAALgAECgIJAwAAAA==.Nostrodom:BAAALgAECgEJAgAAAA==.',
Nu='Nubbs:BAABLgAECn8XAAIYAAkJwRvMCwA8AgAYAAkJwRvMCwA8AgAAAA==.',
Ny='Nyissa:BAAALgADCgYJCQAAAA==.Nyonà:BAAALgADCgQJBAAAAA==.',
Oc='Octas:BAAALgAECgMJAwABLgAFFAQJDgAGABIRAA==.',
Of='Offen:BAAALgAECgIJAgAAAA==.',
Og='Ogmonkas:BAAALgAECgEJAgAAAA==.',
On='Onlyinusa:BAAALgAECgcJEQAAAA==.Onyxnate:BAAALgADCgkJJQAAAA==.',
Op='Opalith:BAAALgAECgIJAgABLgAECgMJAwAQAAAAAA==.Opel:BAAALgADCgUJCAABLgAFFAQJEAAYAIIJAA==.Opi:BAAALgADCgcJBwAAAA==.',
Or='Orbyn:BAAALgADCgEJAQAAAA==.Ortah:BAAALgADCgEJAQAAAA==.',
Ox='Oxyrania:BAAALgADCgEJAQAAAA==.',
Pf='Pfhor:BAAALgAECgYJBgAAAA==.',
Ph='Phillyshiho:BAAALgAECgcJEwABLgAECgkJIQAhAPEQAA==.',
Pi='Pinkdefender:BAAALgAECggJEAABLgAFFAMJCgAKALEYAA==.',
Po='Pokeumon:BAAALgADCgEJAQAAAA==.Poor:BAAALgAECgMJBwAAAA==.Poosistrox:BAACLgAFFH8KAAQKAAMJsRg+JgA8AAAiAAIJYQ4XDACZAAARAAIJ2R/NfABmAAAKAAEJkAU+JgA8AAAuAAQKfyEAAxEACAkoHrUvAHkCABEACAkoHrUvAHkCAAoABAlvBxw3AIkAAAAA.Pornelius:BAAALgAECgcJCwABLgAECggJKwALAKIdAA==.Potumkin:BAAALgADCgQJBgAAAA==.',
Pt='Ptheve:BAACLgAFFH8ZAAMgAAgJUB7bAACgAgAgAAgJUB7bAACgAgASAAIJxSHWEQBvAAAuAAQKfykAAyAACQmvJXcBAMgDACAACQmoJXcBAMgDABIABwmMJKoUACsCAAAA.',
Pu='Pump:BAAALgADCgEJAQAAAA==.Putang:BAAALgAECgEJAQAAAA==.',
['På']='Pållås:BAAALgADCgMJAwAAAA==.',
Qn='Qnyx:BAABLgAECn8hAAIhAAcJQRKnJABRAQAhAAcJQRKnJABRAQAAAA==.',
Ra='Raelindra:BAAALgAECggJEwAAAA==.Rayalla:BAAALgADCgUJBQAAAA==.Raygor:BAAALgAECgYJCwAAAA==.',
Re='Rebuke:BAABLgAECn8aAAIBAAgJeRalNADoAQABAAgJeRalNADoAQAAAA==.',
Ro='Rookorblood:BAAALgAECgYJDwAAAA==.Rosewalker:BAACLgAFFH8SAAIGAAUJ/iIcCACZAQAGAAUJ/iIcCACZAQAuAAQKfzEAAwYACQk9JRMBAEsDAAYACQk9JRMBAEsDABgABgnqFaYlADQBAAAA.Rosewall:BAAALgAECgQJBQABLgAFFAUJEgAGAP4iAA==.Rottgut:BAAALgAECgYJDQAAAA==.',
Ry='Ryachun:BAAALgADCgMJAwAAAA==.Rykò:BAABLgAECn8vAAQTAAkJvhVPKADvAQATAAkJTxVPKADvAQAjAAYJGQdoLADsAAADAAUJ7BA3XgDIAAAAAA==.',
Sa='Salchaos:BAABLgAECn8eAAQLAAgJCRZ5DwCkAQANAAcJiRZPMgDjAQALAAcJ2xR5DwCkAQAMAAQJMxAiLgDRAAAAAA==.Samsmith:BAAALgAECgYJBgAAAA==.Savork:BAABLgAECn8XAAMDAAgJFhCwRgA6AQADAAYJog6wRgA6AQATAAQJwRBzdwDzAAAAAA==.Sayafaed:BAABLgAECn8fAAIgAAkJJQtASABgAQAgAAkJJQtASABgAQAAAA==.Sayamese:BAAALgAECggJEwAAAA==.',
Sc='Scatback:BAABLgAECn8wAAQVAAgJzhmQEAAaAgAVAAgJQhmQEAAaAgAUAAgJhhDUGAC0AQAhAAIJMwk3YgAzAAAAAA==.Schwiddylock:BAAALgAECgUJCgAAAA==.Scud:BAABLgAECn8fAAIhAAkJMw3PHQCCAQAhAAkJMw3PHQCCAQAAAA==.Scáthach:BAAALgADCgYJCAAAAA==.',
Se='Senuna:BAAALgADCgEJAQAAAA==.Seraphae:BAAALgADCgMJAwAAAA==.Seraphnite:BAAALgAECgQJBAAAAA==.',
Sh='Shadowdaddy:BAABLgAECn8hAAIhAAkJ8RALFgDKAQAhAAkJ8RALFgDKAQAAAA==.Shadôwhunt:BAABLgAECn8fAAIRAAgJbhWAXQDaAQARAAgJbhWAXQDaAQAAAA==.Shenlon:BAACLgAFFH8eAAMHAAUJISZoAAC7AQAHAAUJISZoAAC7AQAXAAIJ/iHDFADNAAAuAAQKfy4ABAcACQm+JJMAAI0DAAcACQmPIZMAAI0DAA8ABQlvHdoOAJUBABcABAmKI9AlAI8BAAAA.Shilor:BAABLgAECn8iAAIUAAcJZhlyFQDYAQAUAAcJZhlyFQDYAQAAAA==.Shogun:BAAALgAECgYJCwAAAA==.Shulamite:BAAALgADCgYJBgAAAA==.Shuye:BAAALgAECgMJBAAAAA==.',
Si='Sicarii:BAAALgAECgEJAQABLgAECgcJDgAQAAAAAA==.Sicarrious:BAAALgAECgcJDgAAAA==.Sinaliska:BAAALgADCgQJBAAAAA==.Sinistr:BAABLgAECn8WAAMJAAcJChyjJwDyAQAJAAcJChyjJwDyAQAIAAQJIAUfIgCyAAAAAA==.',
Sk='Skyarc:BAAALgAECgUJBgAAAA==.Skyrun:BAAALgAECgMJAwABLgAECgUJBgAQAAAAAA==.',
Sm='Smiffbrew:BAAALgADCgMJBAAAAA==.Smiffury:BAAALgAECgYJCQAAAA==.',
Sn='Snicks:BAAALgAECgIJAgAAAA==.',
Sq='Squishyshoe:BAAALgAECgEJAQAAAA==.',
St='Stinkythebum:BAAALgAECgYJCQAAAA==.Stoneymalone:BAAALgAECgEJAQAAAA==.Stélle:BAAALgAECggJEAAAAA==.',
Su='Supdude:BAABLgAECn8uAAMEAAkJIyDVBQCQAgAEAAkJIyDVBQCQAgAfAAEJaRz2DQA6AAAAAA==.',
Ta='Tairnbys:BAAALgAECgMJAwAAAA==.Tazbirkloa:BAAALgADCgIJAgAAAA==.',
Te='Tebzerk:BAAALgAECgUJCAAAAA==.Tekk:BAAALgAECgcJCAAAAA==.Temptress:BAAALgADCgIJAwAAAA==.',
Th='Thatssotank:BAAALgAECgMJAwABLgAECgkJNgAFADwbAA==.Thorokk:BAAALgAECgMJAwAAAA==.Thynrage:BAAALgAECgUJBgAAAA==.',
Ti='Tigas:BAABLgAECn8oAAINAAcJ6SQjDABjAgANAAcJ6SQjDABjAgAAAA==.',
To='Tooth:BAAALgAECgEJAgAAAA==.Tor:BAAALgADCgMJAwABLgAECgcJDgAQAAAAAA==.',
Tr='Trashdragon:BAABLgAECn8vAAMHAAgJpCHtAQCBAgAXAAgJLh6yDgCKAgAHAAgJZiDtAQCBAgAAAA==.Trauma:BAAALgAECgMJAwAAAA==.',
Ty='Tygrans:BAAALgADCgUJBQAAAA==.',
['Tö']='Töby:BAAALgAECgcJDAABLgAECgcJDgAQAAAAAA==.',
Ul='Ulric:BAAALgAECgQJBQAAAA==.',
Um='Umgunk:BAAALgAECgQJBQAAAA==.',
Un='Unorthodox:BAAALgAECgUJCAAAAA==.',
Us='Usagi:BAABLgAECn8ZAAIBAAYJBhqPYABoAQABAAYJBhqPYABoAQAAAA==.',
Ut='Utsuro:BAAALgAECgMJAwABLgAECggJDAAQAAAAAA==.',
Va='Vannacutt:BAABLgAECn8UAAINAAgJkgzzKQBjAQANAAgJkgzzKQBjAQABLgAECggJDAAQAAAAAA==.',
Ve='Velzevul:BAAALgADCgYJBgAAAA==.Vermouth:BAAALgAECgUJBQAAAA==.',
Vi='Vincentx:BAAALgADCgUJCwAAAA==.',
Vv='Vvinter:BAAALgAECgEJAQAAAA==.',
Vy='Vynii:BAABLgAECn8pAAMgAAkJ9BMDPQCJAQASAAYJghg8JgCOAQAgAAkJ0w8DPQCJAQAAAA==.',
Wa='Wardamage:BAAALgADCgYJBgAAAA==.Wasabi:BAAALgAECgcJDwAAAA==.',
We='Weenygripper:BAAALgAECgcJEwABLgAFFAQJDQAFAHYiAA==.',
Wo='Wonon:BAAALgAFFAEJAQAAAA==.Wontonboy:BAAALgADCgEJAQAAAA==.',
Wu='Wuufi:BAAALgADCgYJBgAAAA==.',
Xa='Xaam:BAAALgAECgUJCAAAAA==.Xaida:BAACLgAFFH8JAAIWAAUJqA4NEQBUAQAWAAUJqA4NEQBUAQAuAAQKfxUAAgYACQl7DEUbAJABAAYACQl7DEUbAJABAAEuAAUUCQktAA8A+hcA.',
Xe='Xecutioner:BAAALgAECgEJAQAAAA==.',
Xi='Xilantaeki:BAAALgADCgIJAgAAAA==.',
Yq='Yqwegvbwefhu:BAAALgAECgMJBwAAAA==.',
Za='Zangyaku:BAEBLgAECn8gAAIKAAgJ+iUmAwCFAgAKAAgJ+iUmAwCFAgAAAA==.Zanmetsu:BAEBLgAECn8ZAAMEAAcJrRyNGABDAgAEAAcJrRyNGABDAgAeAAEJjgzsHgA4AAABLgAECggJIAAKAPolAA==.Zarlock:BAAALgADCgYJBgAAAA==.',
Ze='Zeji:BAABLgAECn8tAAMJAAkJmxoWDgCWAgAJAAkJmxoWDgCWAgAZAAQJmRpkMgAbAQAAAA==.Zerocool:BAABLgAECn8fAAIkAAkJBRMrQgAGAgAkAAkJBRMrQgAGAgAAAA==.',
Zu='Zuggernaut:BAAALgADCgYJBgAAAA==.Zugquavious:BAAALgAECgcJCAABLgAECgcJDQAQAAAAAA==.Zugzug:BAAALgAECgIJAgAAAA==.',
Zy='Zyggy:BAAALgAECggJEAAAAA==.',
['ßa']='ßadfish:BAABLgAECn8iAAIBAAkJ/CPqGADTAgABAAkJ/CPqGADTAgAAAA==.',
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
