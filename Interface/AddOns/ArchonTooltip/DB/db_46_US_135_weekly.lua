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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Shaman-Elemental','Mage-Frost','DemonHunter-Devourer','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Blood','Monk-Brewmaster','DeathKnight-Frost','Rogue-Subtlety','Paladin-Protection','Priest-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Balance','Warrior-Arms','Paladin-Holy','Monk-Windwalker','Warrior-Fury','Hunter-Survival','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-05-16',data={Ac='Acallia:BAAALgAECgEJAgAAAA==.Achkmed:BAABLgAECn8WAAIBAAcJfhiUZABbAQABAAcJfhiUZABbAQAAAA==.',
Ae='Aelynis:BAABLgAECn8iAAICAAkJOg+VCADFAQACAAkJOg+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn83AAIDAAgJ+glNMwAVAQADAAgJ+glNMwAVAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJLgAEAGUfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgMJBAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.',
An='Annerose:BAABLgAECn8XAAIFAAcJxwLxmwCSAAAFAAcJxwLxmwCSAAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn83AAMEAAkJ5RXEKAA1AgAEAAkJ5RXEKAA1AgAGAAEJiAOJDgAmAAAAAA==.',
Ap='Apollo:BAAALgAECgQJBAAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgcJGgAHAIogAA==.',
Ar='Arcanelotus:BAAALgADCgUJBQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8kAAMIAAkJGRfaGwD+AQAIAAkJGRfaGwD+AQAJAAQJugjVPgC3AAAAAA==.Arilea:BAAALgAECgMJAwAAAA==.Arioriaa:BAABLgAECn8bAAIKAAcJFQv5RgAuAQAKAAcJFQv5RgAuAQAAAA==.Arlind:BAAALgAECgMJBQAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.',
At='Atanatari:BAAALgADCgcJGwABLgAECgMJBQALAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgAECgMJAwAAAA==.Azurdrache:BAAALgAECgEJAgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Bassotan:BAAALgAECggJCwAAAA==.Battleares:BAAALgAECgUJCgAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8eAAIMAAYJpwnMEwDMAAAMAAYJpwnMEwDMAAAAAA==.',
Bi='Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgADCgcJEQAAAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgQJCgAAAA==.',
Bl='Blackendmoon:BAAALgAECgMJCQAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJAwAAAA==.Bluebeary:BAAALgAECgMJAwAAAA==.Bluelocks:BAABLgAECn8oAAMMAAgJjBCyCABvAQAMAAgJjBCyCABvAQANAAEJTgLwEwEkAAAAAA==.Bluéyes:BAAALgAECgQJBwAAAA==.Blvckscvl:BAABLgAECn8hAAMOAAgJvBzsFgCBAgAOAAgJvBzsFgCBAgAPAAEJNQR9kQApAAAAAA==.Blynna:BAAALgAECgEJAQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.Brujha:BAAALgAECgYJBgAAAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJFgABAH4YAA==.',
Ca='Caledra:BAAALgADCgkJCQAAAA==.Calinai:BAAALgAECgIJAgAAAA==.Cambrus:BAAALgADCgkJCQAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8eAAIQAAcJJBLNYQBbAQAQAAcJJBLNYQBbAQAAAA==.',
Ce='Cellturin:BAAALgAECgcJBwAAAA==.',
Ch='Chiarakai:BAAALgADCgYJCgAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Coswell:BAAALgAECgMJAwAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIBAAkJuBADdACTAQABAAkJuBADdACTAQAAAA==.Crixus:BAAALgADCgcJBwAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAABLgAECn8ZAAIRAAYJAAguKgDGAAARAAYJAAguKgDGAAAAAA==.Deathcòw:BAABLgAECn80AAMQAAgJ3CSpDgC7AgAQAAgJ3CSpDgC7AgASAAIJmgkIPgBZAAAAAA==.Detective:BAABLgAECn8XAAITAAkJFQvTOgBdAQATAAkJFQvTOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Diamond:BAAALgADCgkJCQAAAA==.Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8iAAITAAgJ1hhNEAD9AQATAAgJ1hhNEAD9AQAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dp='Dpshut:BAAALgADCgEJAQABLgAECgkJFgABAH4YAA==.',
Dr='Draegare:BAABLgAECn8qAAIBAAgJqCXlBQBuAwABAAgJqCXlBQBuAwAAAA==.Drdeer:BAAALgAECgcJEAAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgAECgMJAwAAAA==.',
Du='Duskraven:BAAALgAECgUJBQAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAAALgAECgYJEAAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgMJBAAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJFgABAH4YAA==.',
Ev='Evang:BAABLgAECn8ZAAIOAAcJaAsZXAA1AQAOAAcJaAsZXAA1AQAAAA==.Eve:BAAALgAFFAMJAwAAAA==.Everd:BAABLgAECn8dAAIBAAgJpQpVagBPAQABAAgJpQpVagBPAQAAAA==.Evren:BAAALgAECgQJBQAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgAECgMJAwAAAA==.',
Fi='Fiametta:BAABLgAECn8pAAIMAAgJeiFbAQCXAgAMAAgJeiFbAQCXAgAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flent:BAABLgAECn8bAAMPAAgJKQvtDQA1AQAPAAgJKQvtDQA1AQAOAAEJqQa64gAzAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgAECgUJCgAAAA==.',
Ga='Gabagoop:BAAALgAECgYJBgAAAA==.Galindlianid:BAABLgAECn8UAAIBAAgJ7QFl1gCVAAABAAgJ7QFl1gCVAAAAAA==.',
Ge='Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgAECgEJAQAAAA==.',
Gi='Gigaweenie:BAAALgADCgUJBQAAAA==.',
Gl='Glavien:BAABLgAECn8iAAIBAAgJkg93XQBtAQABAAgJkg93XQBtAQAAAA==.Global:BAAALgADCgkJCQABLgAECgYJCgALAAAAAA==.',
Go='Gobtjr:BAAALgADCgMJAwAAAA==.',
Gr='Grandstorm:BAAALgADCgIJAgAAAA==.Greg:BAAALgADCgYJBgAAAA==.Grienke:BAAALgADCgQJBAABLgAECggJHgAUAM0dAA==.Grizzle:BAAALgADCgUJBQAAAA==.Grumpolbolt:BAABLgAECn8eAAIVAAgJ9BkuJwC/AQAVAAgJ9BkuJwC/AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAwAAAA==.Haplo:BAAALgAECgMJBAAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQAMAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hellmet:BAAALgAECgMJAwAAAA==.Hey:BAACLgAFFH8IAAIKAAIJphqOFQCsAAAKAAIJphqOFQCsAAAuAAQKfz0AAgoACQmDIDMIAPICAAoACQmDIDMIAPICAAAA.',
Ho='Homble:BAAALgADCgIJAgAAAA==.Horadin:BAAALgAECgMJAwAAAA==.',
Hu='Huntmeister:BAABLgAECn8eAAIOAAgJLyEEDQDWAgAOAAgJLyEEDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8hAAIQAAgJuSLREwCRAgAQAAgJuSLREwCRAgAAAA==.',
Il='Ilharra:BAAALgAECgQJCwAAAA==.Ilililili:BAAALgAECgMJBAAAAA==.Illee:BAAALgAECgcJEgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAECgkJLAASAOsgAA==.Imturtle:BAABLgAECn8sAAMSAAkJ6yDrBQDcAgASAAkJ6yDrBQDcAgAQAAIJ6BA+/gB+AAAAAA==.',
In='Insømniadk:BAABLgAFFH8JAAIQAAMJwiCSTQAZAQAQAAMJwiCSTQAZAQABLgAFFAYJEwAQACQfAA==.',
Is='Isshiny:BAABLgAECn8XAAIBAAcJshldSACkAQABAAcJshldSACkAQAAAA==.Isweat:BAAALgAECgMJAwAAAA==.',
Iu='Iupiter:BAAALgAECgcJEQAAAA==.',
Iy='Iyahlieairia:BAAALgADCgEJAQAAAA==.',
Iz='Izabeth:BAABLgAECn8cAAIEAAcJGA4+dgBOAQAEAAcJGA4+dgBOAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8bAAIWAAcJuwyNGQD4AAAWAAcJuwyNGQD4AAAAAA==.',
Je='Jessabella:BAAALgADCgIJAgAAAA==.',
Ji='Jigles:BAAALgADCgEJAQAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8bAAIKAAgJHgZ4XwAOAQAKAAgJHgZ4XwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgADCgUJAwAAAA==.',
Ki='Kialla:BAAALgADCgYJBgABLgAECgkJFgABAH4YAA==.Kiraneem:BAABLgAECn8kAAMOAAgJgxmsLQDUAQAOAAgJgxmsLQDUAQAPAAEJ2wGjlwAgAAAAAA==.Kittie:BAABLgAECn8qAAMKAAkJgQ4sLgCjAQAKAAkJgQ4sLgCjAQADAAQJjQjdWQB7AAAAAA==.',
Ko='Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8VAAIEAAcJ2xEhcgBWAQAEAAcJ2xEhcgBWAQAAAA==.Krinj:BAABLgAECn8oAAIQAAkJZR34LgD8AQAQAAkJZR34LgD8AQAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Kt='Ktariani:BAAALgADCgUJBQAAAA==.',
Ky='Kyarla:BAABLgAECn8jAAIXAAUJ6hVoKgAsAQAXAAUJ6hVoKgAsAQAAAA==.Kydo:BAABLgAECn8kAAIEAAcJtRiyTQCvAQAEAAcJtRiyTQCvAQABLgAFFAMJBQAYAEYIAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQALAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8hAAMIAAgJnxMRGgChAQAIAAgJnxMRGgChAQAXAAEJpQq5XwAjAAAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECggJHgAUAM0dAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9JAAIVAAgJ6h00DAAUAgAVAAgJ6h00DAAUAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgMJBAAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn8iAAIJAAgJNhpNCwBkAgAJAAgJNhpNCwBkAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8ZAAIFAAgJoBafMQC1AQAFAAgJoBafMQC1AQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgABLgAECgEJBQALAAAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAAALgAECgYJEwAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8cAAIXAAkJBR+1BwCtAgAXAAkJBR+1BwCtAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgQJBgAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAABLgAECn8dAAMNAAkJdSWMOAApAgANAAcJwiWMOAApAgAMAAMJuiJxJwAmAQABLgAFFAIJAwALAAAAAA==.',
Me='Medreaux:BAABLgAECn87AAIXAAgJ3B2VCwBhAgAXAAgJ3B2VCwBhAgAAAA==.Metalknyte:BAABLgAECn8kAAISAAgJ4gzBHAAcAQASAAgJ4gzBHAAcAQAAAA==.',
Mi='Miniknyte:BAABLgAECn8XAAIZAAgJvAuISQAgAQAZAAgJvAuISQAgAQAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8aAAIHAAcJiiBJBgAlAgAHAAcJiiBJBgAlAgAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mollog:BAAALgAECgMJAwAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJQgAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.',
My='Mychelle:BAABLgAECn8iAAIPAAgJTRV3CACpAQAPAAgJTRV3CACpAQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn8vAAIEAAgJLASNnQAFAQAEAAgJLASNnQAFAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgMJBQALAAAAAA==.Nezaeth:BAAALgAECgMJBQAAAA==.Nezum:BAAALgADCgYJCwABLgAECgMJBQALAAAAAA==.',
Ni='Nickoli:BAAALgAECgIJAgAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBQAAAA==.Nojomo:BAAALgAECgEJAQAAAA==.Nojomoto:BAAALgAECgIJAgAAAA==.Norabel:BAAALgAECgYJDQAAAA==.',
Ny='Nyra:BAABLgAECn8jAAIOAAkJ8BptGABIAgAOAAkJ8BptGABIAgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn8uAAMMAAgJ6hcdBQDPAQAMAAgJ6hcdBQDPAQANAAYJ2AuvfgD/AAAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8aAAMaAAcJdSKfHAAdAgAaAAcJdSKfHAAdAgAZAAcJLQ4qXwA0AQAAAA==.',
Ol='Oldben:BAAALgAECgYJCwAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAcJHgAbAKAeAA==.Oriel:BAABLgAECn8kAAIJAAgJKQrKHgB6AQAJAAgJKQrKHgB6AQAAAA==.Orthein:BAAALgAECgEJAQABLgAECgUJCQALAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgEJAQAAAA==.',
Ph='Phindin:BAABLgAECn8qAAMDAAkJZBFXGgC7AQADAAkJZBFXGgC7AQAKAAEJ4QEapQAlAAAAAA==.',
Po='Poc:BAAALgAECgcJEQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgADCgcJDQAAAA==.Primo:BAAALgAECgYJCAAAAA==.Prinsana:BAABLgAECn8kAAIWAAgJGRTSDgB+AQAWAAgJGRTSDgB+AQAAAA==.',
Pu='Purged:BAABLgAECn8aAAIKAAgJxQUETwAOAQAKAAgJxQUETwAOAQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgAAAA==.Ratheer:BAAALgAFFAIJAwAAAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8bAAIcAAcJ6Rj6GADxAQAcAAcJ6Rj6GADxAQAAAA==.',
Rl='Rllybuffnerd:BAAALgAECgEJAQAAAA==.',
Ro='Rodikus:BAABLgAECn8vAAMXAAgJXSL/CwBbAgAXAAgJXSL/CwBbAgAIAAYJ7Ag/NADzAAAAAA==.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAABLgAECn8ZAAIFAAcJWxmGPACJAQAFAAcJWxmGPACJAQAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAdAJwPAA==.',
Sa='Saiaa:BAAALgAECgcJDwAAAA==.Sakeena:BAAALgAECgMJBAAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAAALgAECgUJEAAAAA==.Sattia:BAABLgAECn8xAAIZAAgJnAa5UgD+AAAZAAgJnAa5UgD+AAAAAA==.',
Sc='Scampington:BAAALgADCgkJEwAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIHAAYJXhjrEQA1AQAHAAYJXhjrEQA1AQAAAA==.',
Sh='Sharrow:BAAALgAECgMJAwAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8bAAITAAcJdBC7JgA7AQATAAcJdBC7JgA7AQAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn8nAAIeAAkJ2RgKKAAdAgAeAAkJ2RgKKAAdAgAAAA==.Silque:BAAALgAECgMJAwAAAA==.Simphunter:BAEBLgAECn8sAAIFAAgJAh8VFQBZAgAFAAgJAh8VFQBZAgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8iAAIRAAgJIAuJGgBCAQARAAgJIAuJGgBCAQAAAA==.Sit:BAAALgAECgYJDgAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIFAAkJgSC/GQC6AgAFAAkJgSC/GQC6AgAAAA==.',
Sm='Smothbran:BAAALgADCgEJAQAAAA==.',
Sn='Snapdragon:BAAALgAECgQJBgAAAA==.',
So='Soluna:BAAALgADCgYJBgAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgMJBAAAAA==.',
Sp='Splunk:BAAALgAECgkJEQABLgAECgkJFwATABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAABLgAECn8ZAAIPAAgJKhCYCgBzAQAPAAgJKhCYCgBzAQAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgMJBAAAAA==.Stormkraa:BAAALgAECgYJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECgkJJwAWAAYYAA==.Strawyæ:BAABLgAECn8nAAIWAAkJBhjJBwBgAgAWAAkJBhjJBwBgAgAAAA==.Strike:BAAALgAECgYJCAABLgAFFAQJCwAcANgUAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.',
Ta='Taleranor:BAAALgAECgYJBgAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8mAAMfAAkJcxLCDQAIAgAfAAkJLhDCDQAIAgAPAAYJ8xAkRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgEJAQAAAA==.Teekeez:BAABLgAECn8WAAIEAAYJ4QqD3gA2AQAEAAYJ4QqD3gA2AQAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8jAAIeAAgJexT7HAC3AQAeAAgJexT7HAC3AQAAAA==.Thrushbeard:BAAALgADCgkJHwAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgkJEAAAAA==.',
Tr='Traaze:BAAALgAECgYJDAAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trisky:BAABLgAECn8iAAIcAAYJDxrsHwC4AQAcAAYJDxrsHwC4AQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwALAAAAAA==.Trydént:BAAALgAECgMJBAAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAAALgAECgYJDwABLgAECgkJLAASAOsgAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8oAAIgAAkJZSAWBQBCAgAgAAkJZSAWBQBCAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8eAAIeAAYJ4QTiTQC8AAAeAAYJ4QTiTQC8AAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgADCgMJAwAAAA==.Vistus:BAAALgAECgQJBAAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECggJIgAPAE0VAA==.Voidmeister:BAABLgAECn8WAAIFAAYJ+RIfcgDqAAAFAAYJ+RIfcgDqAAABLgAECggJHgAOAC8hAA==.Voin:BAABLgAECn9DAAMhAAkJDiM5AwAqAwAhAAkJDiM5AwAqAwAeAAQJfRueOQAPAQAAAA==.Vorpine:BAABLgAECn8pAAMIAAkJ7BXaHACIAQAIAAcJkBnaHACIAQAJAAkJsgoUMQD1AAAAAA==.',
Vs='Vs:BAACLgAFFH8GAAIQAAMJ3RJHJQABAQAQAAMJ3RJHJQABAQAuAAQKfxUAAhAACAnYIKhSAPoBABAACAnYIKhSAPoBAAEuAAUUCAkvAAUArCQA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8aAAIYAAgJZxb+FgDuAQAYAAgJZxb+FgDuAQAAAA==.',
Wi='Wirhl:BAABLgAECn8WAAIOAAYJ0RBkYQAnAQAOAAYJ0RBkYQAnAQAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAABLgAFFH8GAAIBAAQJuRebHABPAQABAAQJuRebHABPAQAAAA==.',
Wy='Wyn:BAABLgAECn8jAAIBAAgJRB9CHgBOAgABAAgJRB9CHgBOAgAAAA==.',
Xa='Xalbit:BAABLgAECn8jAAIKAAgJnBtiEQByAgAKAAgJnBtiEQByAgAAAA==.Xanthrash:BAAALgAECgUJCQAAAA==.Xantia:BAABLgAECn83AAIZAAkJfRXlFgBIAgAZAAkJfRXlFgBIAgAAAA==.Xaraena:BAABLgAECn8fAAIOAAkJfRr2KAATAgAOAAkJfRr2KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgUJCAABLgAFFAMJCgAcAI8eAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJFwAiAOoVAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwALAAAAAA==.',
Ze='Zercus:BAABLgAFFH8HAAIBAAMJywkzRgDYAAABAAMJywkzRgDYAAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
Zo='Zoel:BAAALgADCgcJBwABLgAECgcJIgAXAMsWAA==.',
['Ðr']='Ðread:BAABLgAECn8UAAMQAAYJMQuwkwD1AAAQAAYJMQuwkwD1AAAUAAEJYwepGAAtAAAAAA==.',
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
