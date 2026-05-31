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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Warlock-Affliction','Hunter-Survival','Druid-Balance','Warrior-Arms','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-05-30',data={Ac='Acallia:BAAALgAECgQJCwAAAA==.Achkmed:BAABLgAECn8YAAIBAAcJfhh7gQBRAQABAAcJfhh7gQBRAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+glJQgAOAQADAAgJ+glJQgAOAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgQJDAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.Amberina:BAAALgADCgkJCQAAAA==.',
An='Annerose:BAABLgAECn8mAAIFAAgJpgPGqACzAAAFAAgJpgPGqACzAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn89AAMEAAkJDhqZKgBZAgAEAAkJDhqZKgBZAgAGAAEJiAObEgAmAAAAAA==.',
Ap='Apollo:BAAALgAFFAEJAQAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgAECgIJAgAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8qAAIKAAgJJgt8TwBWAQAKAAgJJgt8TwBWAQAAAA==.Arlind:BAAALgAECgQJBwAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.Assuutu:BAAALgADCgMJAwAAAA==.',
At='Atanatari:BAAALgAECgEJAQABLgAECgQJBgALAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azarine:BAAALgADCggJCQAAAA==.Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAABLgAECn8cAAIBAAkJgBafOwD9AQABAAkJgBafOwD9AQAAAA==.Battleares:BAAALgAECgYJEAAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8mAAIMAAcJjgkDFQDmAAAMAAcJjgkDFQDmAAAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgAECgIJAgABLgAFFAQJCQAEAPITAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgYJDwAAAA==.',
Bl='Blackendmoon:BAAALgAECgQJCgAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJBQAAAA==.Bluebeary:BAAALgAECgQJBAAAAA==.Bluelocks:BAABLgAECn8rAAMMAAgJjRDPCwBkAQAMAAgJjRDPCwBkAQANAAEJTgJzQwEkAAAAAA==.Bluéyes:BAAALgAECgQJBwAAAA==.Blvckscvl:BAABLgAECn8hAAMOAAgJvBzsFgCBAgAOAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgYJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.Borrne:BAAALgAECgEJAQAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAAAAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJGAABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8rAAIQAAcJ6hQHcQBuAQAQAAcJ6hQHcQBuAQAAAA==.',
Ce='Cellturin:BAAALgAECgkJEQAAAA==.',
Ch='Chelais:BAAALgAECgQJBAABLgABCgMJAwALAAAAAA==.Chiarakai:BAAALgADCggJEQAAAA==.Chobits:BAAALgAECgUJBgAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAABLgAECn8ZAAIRAAYJAAg0OAC2AAARAAYJAAg0OAC2AAAAAA==.Deathcòw:BAACLgAFFH8FAAIQAAMJDBjdcQD6AAAQAAMJDBjdcQD6AAAuAAQKfzcAAxAACQmuI18LAAIDABAACQmuI18LAAIDABIAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgIJAQALAAAAAA==.Demonhunter:BAAALgAECgEJAQAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJEAAAAA==.Dilligafehno:BAAALgADCgkJCQAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8oAAITAAgJ1hiLFQDvAQATAAgJ1hiLFQDvAQAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgADCgEJAQABLgAECgkJGAABAH4YAA==.',
Dr='Draann:BAAALgADCggJBwABLgAECgQJBwALAAAAAA==.Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Drdeer:BAABLgAECn8WAAIUAAcJ2xHiPACNAQAUAAcJ2xHiPACNAQAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgMJAwAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAAALgAFFAEJAQAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJGAABAH4YAA==.',
Ev='Evang:BAABLgAECn8oAAIOAAgJ5Q7GUACXAQAOAAgJ5Q7GUACXAQAAAA==.Eve:BAAALgAFFAMJAwAAAA==.Everd:BAABLgAECn8wAAIBAAkJFhKkSgDPAQABAAkJFhKkSgDPAQAAAA==.Everett:BAAALgAECgUJCgAAAA==.Evren:BAAALgAFFAEJAQAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAABLgAECn86AAIMAAgJECLGAQCnAgAMAAgJECLGAQCnAgAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flent:BAABLgAECn8bAAMPAAgJKgtUEQAvAQAPAAgJKgtUEQAvAQAOAAEJqQalHgEuAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAAALgAECgcJDwAAAA==.Galindlianid:BAABLgAECn8hAAIBAAgJsAOLzADZAAABAAgJsAOLzADZAAAAAA==.',
Ge='Gernik:BAAALgAECgEJAQAAAA==.Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJAwAAAA==.',
Gh='Ghuldan:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgAFFAIJBAAAAA==.',
Gl='Glavien:BAABLgAECn8oAAIBAAgJlw9JeQBhAQABAAgJlw9JeQBhAQAAAA==.Global:BAAALgADCgkJCQABLgAECgcJKAAGAL0eAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.',
Gr='Grandstorm:BAAALgADCgQJBAAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAECgkJMAAVAPgfAA==.Grizzle:BAAALgADCgUJBQABLgAECgUJBQALAAAAAA==.Grumpolbolt:BAABLgAECn8eAAIWAAgJ9RkuJwC/AQAWAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgQJBQAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgMJBQAAAA==.Hey:BAACLgAFFH8IAAIKAAIJphqOFQCsAAAKAAIJphqOFQCsAAAuAAQKf1AAAgoACQknIhoFAE0DAAoACQknIhoFAE0DAAAA.',
Hi='Hinamori:BAAALgAECggJCAAAAA==.',
Ho='Homble:BAAALgADCgQJBAAAAA==.Horadin:BAAALgAECgMJAwAAAA==.',
Hu='Huntmeister:BAABLgAECn8qAAIOAAgJtyEEDQDWAgAOAAgJtyEEDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuiIxHgCAAgAQAAgJuiIxHgCAAgAAAA==.',
Il='Ilharra:BAAALgAECgUJEAAAAA==.Ilililili:BAAALgAECgQJBQAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAECgkJQAASABkjAA==.Imturtle:BAABLgAECn9AAAMSAAkJGSP5AgAKAwASAAkJGSP5AgAKAwAQAAcJ/xQ4ngAZAQAAAA==.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiBucgD5AAAQAAMJwiBucgD5AAABLgAFFAYJHAAQAOkgAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxluRADhAQABAAgJGxluRADhAQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBAALAAAAAA==.',
Iu='Iupiter:BAAALgAECgcJEwAAAA==.',
Iv='Ivelos:BAAALgADCgIJAwAAAA==.',
Iy='Iyahlieairia:BAAALgAECgUJBQAAAA==.',
Iz='Izabeth:BAABLgAECn8dAAIEAAcJFw5HkwA3AQAEAAcJFw5HkwA3AQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8qAAIXAAgJuA1vFwBJAQAXAAgJuA1vFwBJAQAAAA==.',
Je='Jessabella:BAAALgADCgQJBAAAAA==.Jesyikaxyz:BAAALgAECgIJAgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgAECgEJAQAAAA==.',
['Jä']='Jägermeister:BAAALgAECgIJAwABLgAECgUJBQALAAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kalypso:BAAALgADCgkJCQAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgAECgUJBgAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJGAABAH4YAA==.Kiraneem:BAABLgAECn8rAAMOAAkJzhcUKAAoAgAOAAkJzhcUKAAoAgAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn9DAAMKAAkJHBbiGgBaAgAKAAkJHBbiGgBaAgADAAQJZgzIaACOAAAAAA==.',
Ko='Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchBlewBmAQAEAAgJchBlewBmAQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZh38PwDwAQAQAAkJZh38PwDwAQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgADCgYJCQAAAA==.',
Ky='Kyarla:BAABLgAECn8jAAIYAAUJ6hULNAAeAQAYAAUJ6hULNAAeAQAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQmMdwDTAAAEAAMJfQmMdwDTAAAuAAQKfyYAAgQABwm9GEFeAKwBAAQABwm9GEFeAKwBAAAA.Kythera:BAAALgAECgQJBAAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8nAAMIAAgJ6hOkHwCqAQAIAAgJ6hOkHwCqAQAYAAEJpQrBcAAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgkJMAAVAPgfAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9bAAIWAAkJoR4LCACQAgAWAAkJoR4LCACQAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgQJBQAAAA==.Lovécoil:BAAALgAECgEJAQAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn8lAAIJAAgJ6xpDDwBcAgAJAAgJ6xpDDwBcAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8bAAIFAAgJohazPQC6AQAFAAgJohazPQC6AQAAAA==.',
['Lë']='Lëw:BAAALgAECgIJAgAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQALAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8ZAAIZAAgJLwq+CwBEAQAZAAgJLwq+CwBEAQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIYAAkJBR9ZCQC9AgAYAAkJBR9ZCQC9AgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgYJDAAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAACLgAFFH8FAAMaAAMJVRlpFABaAAANAAIJhRdgewCvAAAaAAEJ8xxpFABaAAAuAAQKfx0AAw0ACQl4JYw4ACkCAA0ABwnEJYw4ACkCAAwAAwm6InEnACYBAAAA.',
Me='Medreaux:BAABLgAECn9NAAIYAAkJuhyiCADLAgAYAAkJuhyiCADLAgAAAA==.Metalknyte:BAABLgAECn8rAAISAAkJlw8iFwCTAQASAAkJlw8iFwCTAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8eAAIUAAkJhAtwSwBOAQAUAAkJhAtwSwBOAQAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiAACQAZAgAHAAcJiiAACQAZAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAFFAEJAQABLgAECgkJIAAFAIIgAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJSwAAAA==.Morghulis:BAAALgAECgUJBQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn8oAAMPAAgJ3hU4CgC0AQAPAAgJ3hU4CgC0AQAbAAIJRwdLTABlAAAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn84AAIEAAgJ6Qn5hABSAQAEAAgJ6Qn5hABSAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgQJBwALAAAAAA==.Nezaeth:BAAALgAECgQJBwAAAA==.Nezum:BAAALgADCgYJDgABLgAECgQJBwALAAAAAA==.',
Ni='Nickoli:BAAALgAECgMJAwAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJAwAAAA==.Nojomoto:BAAALgAECgIJAwAAAA==.Norabel:BAAALgAECgYJDQAAAA==.',
Ny='Nyra:BAABLgAECn8qAAIOAAkJ6B6UDgDJAgAOAAkJ6B6UDgDJAgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn83AAMMAAkJ7BrUAgBlAgAMAAkJ7BrUAgBlAgANAAYJ2AvKnAD6AAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8fAAMcAAkJ2B6vDgBbAgAcAAkJ2B6vDgBbAgAUAAcJLQ4qXwA0AQABLgAFFAMJBQAEAEAEAA==.',
Ol='Oldben:BAAALgAFFAIJBAAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAdAJAfAA==.Oriel:BAABLgAECn8rAAIJAAkJSAphIQCfAQAJAAkJSAphIQCfAQAAAA==.Orthein:BAAALgAECgMJBQABLgAECgcJEAALAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn84AAMDAAkJHRNYIADHAQADAAkJHRNYIADHAQAKAAcJxwUQbwDvAAAAAA==.',
Pi='Pixystix:BAAALgADCgkJCQABLgAECggJKAAPAN4VAA==.',
Po='Poc:BAABLgAECn8gAAIHAAgJ5w+bEwBgAQAHAAgJ5w+bEwBgAQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgAECgkJCgAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn8rAAIXAAkJbBKPDwCvAQAXAAkJbBKPDwCvAQAAAA==.',
Pu='Puddytat:BAAALgADCgMJAwAAAA==.Purged:BAABLgAECn8gAAIKAAkJOAaDVQBAAQAKAAkJOAaDVQBAAQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Py='Pya:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRW8aACPAAAFAAIJSRW8aACPAAABLgAFFAMJBQAaAFUZAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8qAAIeAAgJ1hswEACDAgAeAAgJ1hswEACDAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgIJAgAAAA==.',
Ro='Rodikus:BAACLgAFFH8JAAIYAAQJeRKpEgAPAQAYAAQJeRKpEgAPAQAuAAQKfzsAAxgACQl7IeQOAGACABgACAldIuQOAGACAAgACQmOE+YWAPYBAAAA.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8jAAIFAAgJxRn8MQDoAQAFAAgJxRn8MQDoAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAfAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
Sa='Saiaa:BAAALgAECggJEAAAAA==.Sakeena:BAAALgAECgQJBQAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8WAAIIAAYJrAJ4XAB1AAAIAAYJrAJ4XAB1AAAAAA==.Sattia:BAABLgAECn9DAAIUAAkJzAadVQAnAQAUAAkJzAadVQAnAQAAAA==.',
Sc='Scampington:BAAALgAECgEJAQAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhjSFwAuAQAHAAYJXhjSFwAuAQAAAA==.',
Sh='Sharokk:BAAALgAECgUJBQABLgAECggJIwAFAMUZAA==.Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8qAAMTAAgJURJSJAB3AQATAAgJZxFSJAB3AQAfAAEJug99iAA2AAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn81AAIgAAkJUBz+DQB8AgAgAAkJUBz+DQB8AgAAAA==.Simphunter:BAEBLgAECn83AAIFAAkJfB53DgC9AgAFAAkJfB53DgC9AgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8oAAIRAAgJPgvsIwA0AQARAAgJPgvsIwA0AQAAAA==.Sit:BAAALgAECgcJEAAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smothbran:BAAALgADCgIJAwAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Soluna:BAAALgAECgQJBAAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJBQAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8iAAIPAAkJTxLUCADYAQAPAAkJTxLUCADYAQAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgQJBQAAAA==.Stillwing:BAAALgADCgIJAgAAAA==.Stormkraa:BAAALgAECgkJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJNQAXAHMbAA==.Strawyæ:BAABLgAECn81AAIXAAkJcxuCCAAzAgAXAAkJcxuCCAAzAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAUJEQAeAGYUAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.Suttercane:BAAALgAECgQJBAAAAA==.',
['Sì']='Sìrocco:BAAALgAECgYJBgAAAA==.',
Ta='Taleranor:BAAALgAECgcJEwAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8qAAMbAAkJJBOrEgAHAgAbAAkJBhGrEgAHAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8ZAAIEAAYJ4QqD3gA2AQAEAAYJ4QqD3gA2AQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8pAAIgAAgJLBXzJAC5AQAgAAgJLBXzJAC5AQAAAA==.Thorek:BAAALgADCgkJEAAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trapology:BAAALgAECgEJAQAAAA==.Trisky:BAABLgAECn8rAAMeAAkJ1Bg+GgAdAgAeAAgJjxc+GgAdAgABAAcJNQ7CkwAwAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwALAAAAAA==.Trydént:BAAALgAECgQJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8dAAMNAAYJzhoPVQCRAQANAAYJzhoPVQCRAQAMAAIJmwajPgAiAAABLgAECgkJQAASABkjAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIhAAkJCyF6BQB2AgAhAAkJCyF6BQB2AgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8sAAIgAAcJ9gR6UwDlAAAgAAcJ9gR6UwDlAAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECgIJAgAAAA==.Vistus:BAAALgAECgcJCwAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECggJKAAPAN4VAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RISkADhAAAFAAYJ+RISkADhAAABLgAECggJKgAOALchAA==.Voin:BAABLgAECn9LAAMiAAkJDyM5AwAqAwAiAAkJDyM5AwAqAwAgAAQJfRukTAD9AAAAAA==.Vorpine:BAABLgAECn8uAAMIAAkJKxZOHgDnAQAIAAcJkBlOHgDnAQAJAAkJgwyXHwCtAQAAAA==.',
Vs='Vs:BAACLgAFFH8GAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCAkzAAUAwiQA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMjAAgJZxZWIADwAQAjAAgJZxZWIADwAQAfAAEJHgaSoAAlAAAAAA==.',
Wi='Wirhl:BAABLgAECn8WAAIOAAYJ0RBwgAAlAQAOAAYJ0RBwgAAlAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8OAAIBAAQJQyB0GgB4AQABAAQJQyB0GgB4AQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB9YLQAyAgABAAgJRB9YLQAyAgAAAA==.',
Xa='Xalbit:BAABLgAECn8qAAIKAAkJkhsNEAC5AgAKAAkJkhsNEAC5AgAAAA==.Xanae:BAAALgAECggJBgAAAA==.Xanthrash:BAAALgAECgcJEAAAAA==.Xantia:BAABLgAECn85AAIUAAkJJBZoHABPAgAUAAkJJBZoHABPAgAAAA==.Xaraena:BAABLgAECn8fAAIOAAkJfRr2KAATAgAOAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgYJDgABLgAFFAQJDwAeAHQXAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAkAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.',
Ze='Zercus:BAABLgAFFH8LAAIBAAQJXQmZRAAKAQABAAQJXQmZRAAKAQAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJBwABLgAECggJLQAYAFYTAA==.',
['Ðr']='Ðread:BAABLgAECn8hAAMVAAgJog4YDgBkAQAVAAgJUQ4YDgBkAQAQAAYJEQyPsQD8AAAAAA==.',
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
