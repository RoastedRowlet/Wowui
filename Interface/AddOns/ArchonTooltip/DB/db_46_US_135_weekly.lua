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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','Rogue-Outlaw','Druid-Balance','Warrior-Arms','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Hunter-Survival','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acallia:BAAALgAECgMJBAAAAA==.Achkmed:BAABLgAECn8XAAIBAAcJfhg2bQCjAQABAAcJfhg2bQCjAQAAAA==.',
Ae='Aelynis:BAABLgAECn8mAAICAAkJOw+VCADFAQACAAkJOw+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+gksPQAQAQADAAgJ+gksPQAQAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGgfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgMJBAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.',
An='Annerose:BAABLgAECn8eAAIFAAcJCQOAqgCiAAAFAAcJCQOAqgCiAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn89AAMEAAkJDhpxJgBlAgAEAAkJDhpxJgBlAgAGAAEJiAOgEAAmAAAAAA==.',
Ap='Apollo:BAAALgAECgQJBAAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgADCgUJBQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8iAAIKAAcJkAucUgAyAQAKAAcJkAucUgAyAQAAAA==.Arlind:BAAALgAECgQJBgAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.',
At='Atanatari:BAAALgADCgcJGwABLgAECgQJBgALAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAAALgAECggJEwAAAA==.Battleares:BAAALgAECgUJCgAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8fAAIMAAcJOAm+EwDlAAAMAAcJOAm+EwDlAAAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgAECgIJAgABLgAFFAQJBQAEACgKAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgQJCwAAAA==.',
Bl='Blackendmoon:BAAALgAECgQJCgAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJBAAAAA==.Bluebeary:BAAALgAECgQJBAAAAA==.Bluelocks:BAABLgAECn8rAAMMAAgJjRCRCgBrAQAMAAgJjRCRCgBrAQANAAEJTgJLMgEkAAAAAA==.Bluéyes:BAAALgAECgQJBwAAAA==.Blvckscvl:BAABLgAECn8hAAMOAAgJvBzsFgCBAgAOAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgYJBwAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJDAABLgAECgkJOAAFABQaAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJFwABAH4YAA==.',
Ca='Caledra:BAAALgAECgEJAQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8lAAIQAAcJ6hRtaABxAQAQAAcJ6hRtaABxAQAAAA==.',
Ce='Cellturin:BAAALgAECgkJEAAAAA==.',
Ch='Chiarakai:BAAALgADCggJEQAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Corvany:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuRADdACTAQABAAkJuRADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAABLgAECn8ZAAIRAAYJAAg6MwC6AAARAAYJAAg6MwC6AAAAAA==.Deathcòw:BAACLgAFFH8FAAIQAAMJDBjeYgAGAQAQAAMJDBjeYgAGAQAuAAQKfzcAAxAACQmuI4UJAAcDABAACQmuI4UJAAcDABIAAgmaCQg+AFkAAAAA.Deathpanthr:BAAALgAECgEJAQABLgAECgIJAQALAAAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJEAAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8mAAITAAgJ1hjWEwDyAQATAAgJ1hjWEwDyAQAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgADCgEJAQABLgAECgkJFwABAH4YAA==.',
Dr='Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Drdeer:BAABLgAECn8UAAIUAAcJDBCAQABtAQAUAAcJDBCAQABtAQAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgMJAwAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAAALgAECgYJEAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgQJBQAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJFwABAH4YAA==.',
Ev='Evang:BAABLgAECn8gAAIOAAcJUgzraABCAQAOAAcJUgzraABCAQAAAA==.Eve:BAAALgAFFAMJAwABLgAFFAUJCAABAMMaAA==.Everd:BAABLgAECn8oAAIBAAkJMQ5eTgC+AQABAAkJMQ5eTgC+AQAAAA==.Evren:BAAALgAFFAEJAQAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.Feârless:BAAALgAECgYJBgAAAA==.',
Fi='Fiametta:BAABLgAECn8yAAIMAAgJECJ9AQCpAgAMAAgJECJ9AQCpAgAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flent:BAABLgAECn8bAAMPAAgJKgsbEAAyAQAPAAgJKgsbEAAyAQAOAAEJqQYZBAEyAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAAALgAECgYJCAAAAA==.Galindlianid:BAABLgAECn8bAAIBAAgJLAOqwgDhAAABAAgJLAOqwgDhAAAAAA==.',
Ge='Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgIJAgAAAA==.',
Gi='Gigaweenie:BAAALgADCgUJBQAAAA==.',
Gl='Glavien:BAABLgAECn8mAAIBAAgJlw9MawB4AQABAAgJlw9MawB4AQAAAA==.Global:BAAALgADCgkJCQABLgAECgYJDAALAAAAAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.',
Gr='Grandstorm:BAAALgADCgIJAgAAAA==.Greg:BAAALgADCgYJCAAAAA==.Grienke:BAAALgADCgQJBAABLgAECgkJJwAVAKgcAA==.Grizzle:BAAALgADCgUJBQAAAA==.Grumpolbolt:BAABLgAECn8eAAIWAAgJ9RkuJwC/AQAWAAgJ9RkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgQJBQAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgMJBAAAAA==.Hey:BAACLgAFFH8IAAIKAAIJphqOFQCsAAAKAAIJphqOFQCsAAAuAAQKf0cAAgoACQl9ITMIAPICAAoACQl9ITMIAPICAAAA.',
Ho='Homble:BAAALgADCgIJAgAAAA==.Horadin:BAAALgAECgMJAwAAAA==.',
Hu='Huntmeister:BAABLgAECn8gAAIOAAgJLyEEDQDWAgAOAAgJLyEEDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuiLIGgCEAgAQAAgJuiLIGgCEAgAAAA==.',
Il='Ilharra:BAAALgAECgQJCwAAAA==.Ilililili:BAAALgAECgQJBQAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAECgkJOgASABkjAA==.Imturtle:BAABLgAECn86AAMSAAkJGSPxAgD+AgASAAkJGSPxAgD+AgAQAAYJyhU+/gB+AAAAAA==.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiCsYwAEAQAQAAMJwiCsYwAEAQABLgAFFAYJFwAQAC0fAA==.',
Is='Isshiny:BAABLgAECn8ZAAIBAAgJGxn1OwD0AQABAAgJGxn1OwD0AQAAAA==.Isweat:BAAALgAECgMJAwABLgAECgQJBAALAAAAAA==.',
Iu='Iupiter:BAAALgAECgcJEQAAAA==.',
Iy='Iyahlieairia:BAAALgADCgEJAQAAAA==.',
Iz='Izabeth:BAABLgAECn8dAAIEAAcJFw7ohwBLAQAEAAcJFw7ohwBLAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8iAAIXAAcJKg3KHAABAQAXAAcJKg3KHAABAQAAAA==.',
Je='Jessabella:BAAALgADCgIJAgAAAA==.',
Ji='Jifycornbred:BAAALgAECgMJAwAAAA==.Jigles:BAAALgADCgEJAQAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8gAAIKAAkJzQV4XwAOAQAKAAkJzQV4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgAECgUJBQAAAA==.',
Ki='Kialla:BAAALgADCgYJCQABLgAECgkJFwABAH4YAA==.Kiraneem:BAABLgAECn8mAAMOAAgJgxmFNQDdAQAOAAgJgxmFNQDdAQAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn86AAMKAAkJjw/ANQCpAQAKAAkJjw/ANQCpAQADAAQJZgxiYQCOAAAAAA==.',
Ko='Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8XAAIEAAgJchAubwB/AQAEAAgJchAubwB/AQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZh12OgD0AQAQAAkJZh12OgD0AQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgADCgYJCAAAAA==.',
Ky='Kyarla:BAABLgAECn8jAAIYAAUJ6hVgMAAnAQAYAAUJ6hVgMAAnAQAAAA==.Kydo:BAACLgAFFH8HAAIEAAMJfQmCbADdAAAEAAMJfQmCbADdAAAuAAQKfyYAAgQABwm9GLRYALYBAAQABwm9GLRYALYBAAAA.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8lAAMIAAgJ1RO+HQCwAQAIAAgJ1RO+HQCwAQAYAAEJpQqgagAgAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgkJJwAVAKgcAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9YAAIWAAgJvh75CwBBAgAWAAgJvh75CwBBAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgQJBQAAAA==.Lovécoil:BAAALgAECgEJAQAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn8jAAIJAAgJNhpcDgBbAgAJAAgJNhpcDgBbAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8ZAAIFAAgJohaiPAC0AQAFAAgJohaiPAC0AQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQALAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAABLgAECn8WAAIZAAgJEwl1CwA0AQAZAAgJEwl1CwA0AQAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8gAAIYAAkJBR9SCADCAgAYAAkJBR9SCADCAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgYJDAAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAABLgAECn8dAAMNAAkJeCWMOAApAgANAAcJxCWMOAApAgAMAAMJuiJxJwAmAQABLgAFFAIJBQAFAEkVAA==.',
Me='Medreaux:BAABLgAECn9KAAIYAAgJVR+5CQCpAgAYAAgJVR+5CQCpAgAAAA==.Metalknyte:BAABLgAECn8mAAISAAgJIA6RIQAXAQASAAgJIA6RIQAXAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8ZAAIUAAgJfQzZTwAsAQAUAAgJfQzZTwAsAQAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiACCAAgAgAHAAcJiiACCAAgAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mogden:BAAALgAECgQJBgABLgAECgkJIAAFAIIgAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJQgAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.Mukakin:BAAALgADCgEJAQAAAA==.',
My='Mychelle:BAABLgAECn8mAAIPAAgJ3hVuCQC3AQAPAAgJ3hVuCQC3AQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn82AAIEAAgJrQlKhABSAQAEAAgJrQlKhABSAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgQJBgALAAAAAA==.Nezaeth:BAAALgAECgQJBgAAAA==.Nezum:BAAALgADCgYJCwABLgAECgQJBgALAAAAAA==.',
Ni='Nickoli:BAAALgAECgMJAwAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgMJAwAAAA==.Nojomoto:BAAALgAECgIJAwAAAA==.Norabel:BAAALgAECgYJDQAAAA==.',
Ny='Nyra:BAABLgAECn8qAAIOAAkJ6B6zCwDSAgAOAAkJ6B6zCwDSAgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn8yAAMMAAgJfRipBQDiAQAMAAgJfRipBQDiAQANAAYJ2AvVkwD+AAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8cAAMaAAgJxCFAEwASAgAaAAgJxCFAEwASAgAUAAcJLQ4qXwA0AQABLgAFFAcJFwAIALYTAA==.',
Ol='Oldben:BAAALgAFFAIJAgAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAgJJAAbAJAfAA==.Oriel:BAABLgAECn8mAAIJAAgJegrIJAB5AQAJAAgJegrIJAB5AQAAAA==.Orthein:BAAALgAECgEJAgABLgAECgYJDAALAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgQJBAAAAA==.',
Ph='Phindin:BAABLgAECn8zAAMDAAkJHRNIHQDLAQADAAkJHRNIHQDLAQAKAAcJxwWlZgDvAAAAAA==.',
Po='Poc:BAABLgAECn8YAAIHAAcJKwukGQAHAQAHAAcJKwukGQAHAQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgAECgQJBAAAAA==.Primo:BAAALgAECgYJDAAAAA==.Prinsana:BAABLgAECn8mAAIXAAgJZBT4EACIAQAXAAgJZBT4EACIAQAAAA==.',
Pu='Purged:BAABLgAECn8gAAIKAAkJOAYOTwBAAQAKAAkJOAYOTwBAAQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.Ratheer:BAABLgAFFH8FAAIFAAIJSRUCXgCYAAAFAAIJSRUCXgCYAAAAAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8iAAIcAAcJ8RxRFgAxAgAcAAcJ8RxRFgAxAgAAAA==.',
Rh='Rhoana:BAAALgADCgcJBwAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgEJAQAAAA==.',
Ro='Rodikus:BAABLgAECn81AAMYAAgJXSI/DwBNAgAYAAgJXSI/DwBNAgAIAAcJYRAoKQBeAQAAAA==.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8gAAIFAAcJOBrXPwCoAQAFAAcJOBrXPwCoAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAdAJwPAA==.',
Ru='Rukus:BAAALgADCgQJBAAAAA==.',
Sa='Saiaa:BAAALgAECggJEAAAAA==.Sakeena:BAAALgAECgQJBQAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAABLgAECn8WAAIIAAYJrAKkUwCMAAAIAAYJrAKkUwCMAAAAAA==.Sattia:BAABLgAECn86AAIUAAkJiAb+UQAkAQAUAAkJiAb+UQAkAQAAAA==.',
Sc='Scampington:BAAALgAECgEJAQAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhiiFQAzAQAHAAYJXhiiFQAzAQAAAA==.',
Sh='Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8iAAITAAcJ8RC9LAA3AQATAAcJ8RC9LAA3AQAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn8wAAIeAAkJdBrADgBkAgAeAAkJdBrADgBkAgAAAA==.Simphunter:BAEBLgAECn81AAIFAAkJvBzYDwCpAgAFAAkJvBzYDwCpAgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8mAAIRAAgJPgtGIAA7AQARAAgJPgtGIAA7AQAAAA==.Sit:BAAALgAECgYJDgAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgiC/GQC6AgAFAAkJgiC/GQC6AgAAAA==.',
Sl='Slït:BAAALgADCgIJAgAAAA==.',
Sm='Smothbran:BAAALgADCgEJAQAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Soluna:BAAALgADCgYJBgAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgQJBQAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8bAAIPAAgJoRCxDABvAQAPAAgJoRCxDABvAQAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgQJBQAAAA==.Stormkraa:BAAALgAECgYJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJMAAXAIsaAA==.Strawyæ:BAABLgAECn8wAAIXAAkJixrJBwBgAgAXAAkJixrJBwBgAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAQJDAAcABYYAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.',
Ta='Taleranor:BAAALgAECgcJDQAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8mAAMfAAkJdBLREQACAgAfAAkJLhDREQACAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgYJCAAAAA==.Teekeez:BAABLgAECn8WAAIEAAYJ4QqD3gA2AQAEAAYJ4QqD3gA2AQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8nAAIeAAgJLBWEIQC/AQAeAAgJLBWEIQC/AQAAAA==.Thorek:BAAALgADCgcJBwAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trisky:BAABLgAECn8pAAMcAAgJyBqqJgCuAQAcAAYJDxqqJgCuAQABAAcJNQ7GgwBHAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwALAAAAAA==.Trydént:BAAALgAECgQJBQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAABLgAECn8VAAMNAAYJhRc6YgBlAQANAAYJhRc6YgBlAQAMAAEJmwYXOgAkAAABLgAECgkJOgASABkjAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Un='Unhenged:BAAALgADCgQJBAAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8sAAIgAAkJCyGyBAB7AgAgAAkJCyGyBAB7AgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8fAAIeAAcJjwREUQDaAAAeAAcJjwREUQDaAAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgAECgIJAgAAAA==.Vistus:BAAALgAECgQJBAAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECggJJgAPAN4VAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RKphADtAAAFAAYJ+RKphADtAAABLgAECggJIAAOAC8hAA==.Voin:BAABLgAECn9JAAMhAAkJDyM5AwAqAwAhAAkJDyM5AwAqAwAeAAQJfRvrRgAAAQAAAA==.Vorpine:BAABLgAECn8pAAMIAAkJ7BVOHgDnAQAIAAcJkBlOHgDnAQAJAAkJswpkHQCzAQAAAA==.',
Vs='Vs:BAACLgAFFH8GAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCAkzAAUAwiQA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8cAAMiAAgJZxYCHQDvAQAiAAgJZxYCHQDvAQAdAAEJHgYrkwAlAAAAAA==.',
Wi='Wirhl:BAABLgAECn8WAAIOAAYJ0RD4dQAlAQAOAAYJ0RD4dQAlAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8KAAIBAAQJiR8HFwB3AQABAAQJiR8HFwB3AQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB8OKABBAgABAAgJRB8OKABBAgAAAA==.',
Xa='Xalbit:BAABLgAECn8lAAIKAAgJnBuhFgBoAgAKAAgJnBuhFgBoAgAAAA==.Xanae:BAAALgAECgYJBgAAAA==.Xanthrash:BAAALgAECgYJDAAAAA==.Xantia:BAABLgAECn85AAIUAAkJJBYZGgBRAgAUAAkJJBYZGgBRAgAAAA==.Xaraena:BAABLgAECn8fAAIOAAkJfRr2KAATAgAOAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgYJDgABLgAFFAQJDgAcAHQXAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJGAAjAH8YAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.',
Ze='Zercus:BAABLgAFFH8KAAIBAAQJXQlWOQAZAQABAAQJXQlWOQAZAQAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJBwABLgAECgcJKQAYAJAUAA==.',
['Ðr']='Ðread:BAABLgAECn8ZAAMQAAYJEQxqpQD8AAAQAAYJEQxqpQD8AAAVAAIJYwepGAAtAAAAAA==.',
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
