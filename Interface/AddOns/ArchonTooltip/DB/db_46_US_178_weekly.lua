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

local lookup = {'Mage-Fire','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Druid-Balance','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','Rogue-Subtlety','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Priest-Discipline','Monk-Mistweaver','Monk-Brewmaster','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','DemonHunter-Vengeance','Druid-Feral','Warlock-Demonology','Mage-Arcane','Warlock-Destruction','Unknown-Unknown',}
local provider = {region='US',realm='Ravenholdt',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aenastrian:BAAALgADCgEJAQAAAA==.',
Ag='Agnetha:BAAALgAECgUJBQAAAA==.',
Ah='Ahote:BAABLgAECn8qAAIBAAgJgSELAQCbAgABAAgJgSELAQCbAgAAAA==.',
Ai='Airrows:BAABLgAECn82AAMCAAkJdyTpAAAmAwACAAkJdyTpAAAmAwADAAQJKRjGNgDUAAAAAA==.',
Ak='Akon:BAAALgADCgkJDgAAAA==.',
Al='Alatar:BAAALgADCgEJAQAAAA==.Alejandro:BAAALgADCgYJBgAAAA==.Alevill:BAAALgADCgEJAQAAAA==.Almitywitey:BAAALgAECgYJDAAAAA==.Alurea:BAABLgAECn8tAAMEAAgJgAmIVgAVAQAEAAgJgAmIVgAVAQAFAAYJWQspPwDgAAAAAA==.',
An='Ang:BAABLgAECn8dAAIGAAgJkRLQLAABAgAGAAgJkRLQLAABAgAAAA==.Angelious:BAAALgADCgcJBwAAAA==.Anonylyss:BAAALgAECgIJAgAAAA==.Anvi:BAAALgADCgMJAwAAAA==.',
Ap='Apathy:BAABLgAECn8pAAIHAAkJbxnzEgBUAgAHAAkJbxnzEgBUAgAAAA==.Aphridites:BAAALgAECgYJBgAAAA==.',
Ar='Ara:BAABLgAECn8UAAIHAAcJLyJ1GABPAgAHAAcJLyJ1GABPAgAAAA==.Ardagni:BAAALgAECgEJAgAAAA==.Argonäut:BAABLgAECn84AAIIAAkJDyVDAQBOAwAIAAkJDyVDAQBOAwAAAA==.Arimalo:BAAALgAECgQJBAAAAA==.Arkeenkami:BAAALgADCgcJBwAAAA==.',
As='Asmindissa:BAABLgAECn8yAAIJAAkJPRDCSgDfAQAJAAkJPRDCSgDfAQAAAA==.Astragos:BAABLgAECn8iAAQKAAgJaRw0CABLAgAKAAcJVB00CABLAgALAAcJwBv2BgCwAQAMAAcJwhA4OAAVAQAAAA==.',
Az='Azagorod:BAAALgAECgYJBgAAAA==.',
Ba='Baern:BAABLgAECn8sAAMNAAgJHiQfBADJAgANAAgJHiQfBADJAgAOAAIJOxKbXAA2AAAAAA==.',
Be='Beastius:BAAALgAECgIJBAAAAA==.Beleth:BAABLgAECn8UAAICAAYJ6BlRLwC6AQACAAYJ6BlRLwC6AQAAAA==.',
Bi='Billamong:BAABLgAECn8tAAIPAAgJ3RqnEQARAgAPAAgJ3RqnEQARAgAAAA==.Biren:BAAALgAECgQJBQAAAA==.',
Bk='Bk:BAAALgADCgUJBQAAAA==.',
Bl='Blacktemplar:BAAALgAECgEJAQAAAA==.Blitzer:BAABLgAECn8ZAAIQAAcJlwuiDgBHAQAQAAcJlwuiDgBHAQAAAA==.',
Bo='Boarealis:BAAALgAECgQJBAAAAA==.Boney:BAAALgAECgEJAgAAAA==.Boofs:BAAALgADCgIJAgAAAA==.',
Br='Bransel:BAABLgAECn80AAIJAAkJMBo0LwA+AgAJAAkJMBo0LwA+AgAAAA==.Brightstorm:BAAALgAECgIJAgAAAA==.',
Bu='Bubbles:BAAALgAECgEJAQAAAA==.Bucko:BAABLgAFFH8JAAIRAAMJEBh4CQDPAAARAAMJEBh4CQDPAAABLgAFFAcJGQAJABgTAA==.',
Ca='Cahfargus:BAAALgAECgYJBgAAAA==.Caiki:BAAALgAECggJEgAAAA==.Cassilune:BAAALgAECgEJAQABLgAECgkJFgAHAI8XAA==.Catelaya:BAABLgAECn84AAISAAkJYyDpDwCqAgASAAkJYyDpDwCqAgAAAA==.Cathulu:BAAALgAFFAEJAQAAAA==.',
Ce='Celithatha:BAABLgAECn8dAAITAAkJaw+/OgC7AQATAAkJaw+/OgC7AQAAAA==.',
Ch='Chaness:BAACLgAFFH8GAAIUAAIJDiSaVgDRAAAUAAIJDiSaVgDRAAAuAAQKfxkAAhQACAl+GutDABgCABQACAl+GutDABgCAAAA.Chexk:BAABLgAECn8wAAIVAAkJbiDqBADLAgAVAAkJbiDqBADLAgAAAA==.Chillfu:BAABLgAECn8hAAIPAAkJ8xa/EAAcAgAPAAkJ8xa/EAAcAgAAAA==.Chixnu:BAAALgAECgYJDAAAAA==.',
Co='Comicon:BAAALgADCgUJBQAAAA==.Corvina:BAAALgAECgcJBwAAAA==.',
Cr='Cratos:BAAALgAECgEJAQAAAA==.Crush:BAAALgAFFAIJBAABLgAFFAQJDgAEAMceAA==.Cryblood:BAABLgAECn8iAAIWAAgJRxJKIQCUAQAWAAgJRxJKIQCUAQAAAA==.',
Cu='Cutsiecow:BAABLgAECn88AAIXAAkJGxvtBQByAgAXAAkJGxvtBQByAgAAAA==.',
Cy='Cynthic:BAAALgAECgQJCwAAAA==.Cynthìa:BAAALgADCgUJBQAAAA==.',
Da='Dalynn:BAABLgAECn8pAAIUAAgJ1gwYbgByAQAUAAgJ1gwYbgByAQAAAA==.',
De='Deatee:BAAALgADCgIJAgAAAA==.Deathbonk:BAAALgAECgEJAwAAAA==.Deirdra:BAAALgADCgEJAQAAAA==.Demerzel:BAAALgADCgkJCQAAAA==.Demons:BAAALgADCgEJAQAAAA==.',
Dj='Djiinar:BAABLgAECn8oAAINAAgJfB+TCQCBAgANAAgJfB+TCQCBAgAAAA==.Djiink:BAABLgAECn8aAAMYAAgJ/BRJGABwAQAYAAgJ/BRJGABwAQAZAAEJngMqVgEhAAAAAA==.Djiinra:BAAALgAECgQJBAAAAA==.Djiinz:BAAALgAECgMJBQAAAA==.',
Do='Doomlocke:BAAALgAECgMJAwAAAA==.',
Dr='Drakatoa:BAAALgAECgEJAQAAAA==.Drottningu:BAABLgAECn8yAAITAAkJew8hPwCrAQATAAkJew8hPwCrAQAAAA==.',
Du='Dunkie:BAAALgAECgYJEQAAAA==.',
Eb='Ebonymoon:BAAALgAECgMJAwAAAA==.',
Ei='Eiren:BAAALgAECgIJAgAAAA==.',
El='Electro:BAAALgADCgIJAgAAAA==.Elise:BAAALgADCgcJBwABLgAFFAUJBwAYAMUTAA==.Ellaryas:BAAALgAECgIJAgAAAA==.',
Em='Em:BAACLgAFFH8NAAIaAAUJ6BGqFAB5AQAaAAUJ6BGqFAB5AQAuAAQKfxcABBoACQltHEMPAEkCABoACQltHEMPAEkCABYABAlQEVlGAMwAABEAAQk1DSaCAC8AAAAA.',
Er='Eraline:BAABLgAECn89AAIbAAkJlBc5EQBhAgAbAAkJlBc5EQBhAgAAAA==.Eryz:BAAALgAECgIJAgAAAA==.',
Es='Esmiel:BAAALgAECgEJAgAAAA==.',
Fa='Faelyn:BAAALgADCgMJAwAAAA==.Fanz:BAAALgAECgQJBgAAAA==.',
Fe='Fearless:BAABLgAECn8cAAIZAAcJwCLRPADsAQAZAAcJwCLRPADsAQAAAA==.',
Fi='Fizzlepriest:BAAALgAECgUJDgABLgAECggJNAAUAM4fAQ==.',
Fl='Flaciddream:BAAALgAECgUJCwAAAA==.',
Fr='Frostblood:BAAALgAECgcJCQAAAA==.Frostlight:BAAALgAECgYJCAAAAA==.Froststorm:BAAALgAECgIJAgAAAA==.',
Fu='Funder:BAAALgADCgEJAQAAAA==.Funk:BAACLgAFFH8gAAIcAAgJLRhYAgA9AgAcAAgJLRhYAgA9AgAuAAQKfyQAAhwACQnCI1gDAAQDABwACQnCI1gDAAQDAAAA.',
Ge='Genivan:BAAALgAECggJCAAAAA==.Genocya:BAAALgAECgYJEAAAAA==.',
Gh='Ghost:BAABLgAECn8ZAAIdAAgJlBO1BwDjAQAdAAgJlBO1BwDjAQAAAA==.',
Gi='Gilden:BAABLgAECn8ZAAMeAAYJlQgXagDkAAAeAAYJlQgXagDkAAAfAAMJYgOfcQBdAAAAAA==.',
Gn='Gnot:BAAALgAECggJCQAAAA==.',
Go='Goshujinsama:BAAALgADCgMJAwAAAA==.',
Gr='Gromit:BAABLgAECn8yAAMEAAgJVBq5HQBQAgAEAAgJVBq5HQBQAgAFAAUJXBOWMwAaAQAAAA==.',
Gy='Gyoza:BAAALgAECgkJDwABLgAECgkJKQAHAG8ZAA==.',
['Gò']='Gòddess:BAABLgAECn8bAAIIAAgJiBR5EwDAAQAIAAgJiBR5EwDAAQAAAA==.',
['Gö']='Görê:BAAALgADCgYJDwAAAA==.',
Ha='Habrak:BAAALgADCgEJAQAAAA==.Hannahsmad:BAAALgADCgQJBAAAAA==.Haptic:BAAALgADCgcJDAAAAA==.Harlee:BAAALgADCggJDQAAAA==.Haterz:BAAALgAECgEJAgAAAA==.Haukkah:BAABLgAECn8uAAMSAAkJfBPuLwDzAQASAAkJfBPuLwDzAQACAAcJHAW+TQAaAQAAAA==.Hawktuwah:BAAALgADCgUJCAAAAA==.',
He='Healenciago:BAAALgADCgEJAQAAAA==.Heartless:BAAALgADCgkJDQAAAA==.Heffalump:BAAALgADCgcJBwAAAA==.',
If='Ifa:BAABLgAECn8VAAIEAAYJmQxgWwAEAQAEAAYJmQxgWwAEAQAAAA==.',
Im='Imperfect:BAAALgADCgcJDgAAAA==.',
In='Inazuma:BAABLgAECn88AAQKAAgJqRbSCQAkAgAKAAgJqRbSCQAkAgALAAQJkA/rEADYAAAMAAQJhAp8XQCUAAAAAA==.Inazumaw:BAAALgADCgEJAgAAAA==.Inazumma:BAAALgAECggJCwAAAA==.',
Is='Ishatani:BAABLgAECn8YAAQUAAYJ/g1xpgAMAQAUAAYJrw1xpgAMAQAgAAQJawn5LgCAAAAHAAEJoQGbjQAdAAAAAA==.Isilod:BAAALgAECgcJDgAAAA==.',
Iw='Iwantmore:BAABLgAECn8rAAMIAAkJeSQ2AwBSAwAIAAkJySM2AwBSAwAhAAkJ3yAeAgDJAgAAAA==.',
Iy='Iyotanka:BAAALgAECgEJAgAAAA==.',
Jo='Johan:BAAALgADCgEJAQAAAA==.',
Ju='Juicebox:BAABLgAECn8ZAAMXAAgJ5AcmLwCoAAAiAAYJmAcyIQDTAAAXAAcJyQYmLwCoAAABLgAFFAMJCwAcAGYBAA==.Juuzau:BAAALgAECgcJDgAAAA==.',
['Jå']='Jåmes:BAAALgADCgUJBgAAAA==.',
Ka='Kaelthesar:BAACLgAFFH8LAAIaAAQJ4gr+HQAaAQAaAAQJ4gr+HQAaAQAuAAQKfy4AAhoACAljFHUVAP8BABoACAljFHUVAP8BAAAA.Kaners:BAAALgAFFAMJAwAAAA==.Kasey:BAAALgAECgQJBAAAAA==.Kasyrra:BAAALgAECgMJAwAAAA==.Katheryn:BAABLgAECn8mAAIUAAcJDyE4MwASAgAUAAcJDyE4MwASAgAAAA==.Kathyra:BAAALgAECgEJAQABLgAECgcJJgAUAA8hAA==.Katie:BAAALgAECgcJDQABLgAFFAgJIgAeAA8hAA==.',
Ke='Kealey:BAAALgAECgYJEwAAAA==.Keine:BAAALgAECgQJBAAAAA==.Kessik:BAABLgAECn8eAAMGAAkJgxP4MgBZAQAGAAkJRRD4MgBZAQAOAAUJ4xFdLADqAAAAAA==.',
Kh='Khaless:BAABLgAECn8ZAAINAAYJNRH4IQD4AAANAAYJNRH4IQD4AAAAAA==.',
Ki='Kiamors:BAABLgAECn8sAAMfAAgJFwJuVwCuAAAfAAgJFwJuVwCuAAAeAAEJdwHoqwAcAAAAAA==.Kieru:BAAALgADCgkJEgABLgAECgkJKQAHAG8ZAA==.Kilowog:BAAALgADCgUJBQAAAA==.',
Ko='Korvelli:BAAALgAECgQJBwAAAA==.',
Kr='Kragzug:BAABLgAECn8mAAMGAAkJWCIJAwAkAwAGAAkJWCIJAwAkAwAOAAIJUQqyZQAqAAAAAA==.Kreleing:BAAALgAECgQJBAAAAA==.',
La='Labiaminoris:BAAALgADCgUJBAAAAA==.Lakan:BAAALgAECgIJAgAAAA==.Latamoonra:BAAALgAECgYJCgAAAA==.',
Le='Leda:BAAALgAECgEJAgAAAA==.Leionidas:BAAALgADCgkJCQAAAA==.Lexy:BAAALgAECgYJBgAAAA==.',
Li='Liandra:BAABLgAECn8VAAMRAAYJ6wWYTwD6AAARAAYJ6wWYTwD6AAAWAAUJUgYkUACdAAAAAA==.Lightfighter:BAABLgAECn8ZAAMUAAgJTgwPdQBkAQAUAAgJZgsPdQBkAQAgAAQJlwr1LgCAAAABLgAECgkJFAAJAOkEAA==.Lighthouse:BAAALgADCgMJAwAAAA==.Lightmender:BAAALgADCgQJBAABLgAECgkJFAAJAOkEAA==.Lilkiwi:BAABLgAECn8ZAAIJAAYJXQ2BqgAPAQAJAAYJXQ2BqgAPAQAAAA==.',
Lo='Louhfu:BAABLgAECn8YAAIUAAcJdBVlcQBrAQAUAAcJdBVlcQBrAQAAAA==.',
Lu='Lunchbox:BAABLgAECn8jAAIDAAcJYQkYKAA8AQADAAcJYQkYKAA8AQAAAA==.Lunecy:BAABLgAECn8uAAQDAAkJJB9zBQC3AgADAAkJwx5zBQC3AgASAAUJdSCIQwCiAQACAAEJaQc2jwAsAAAAAA==.',
Ma='Magul:BAACLgAFFH8OAAIJAAQJhg44SwAyAQAJAAQJhg44SwAyAQAuAAQKfzUAAgkACAntG1NJAOQBAAkACAntG1NJAOQBAAAA.Makilandria:BAAALgADCgIJAgAAAA==.Manmaru:BAAALgADCgkJCQAAAA==.Matty:BAAALgAECgYJCgABLgAFFAcJGQAJABgTAA==.Mazikeenx:BAAALgADCgEJAQAAAA==.',
Mc='Mcpheex:BAABLgAECn8YAAIFAAgJhQzCKwBIAQAFAAgJhQzCKwBIAQAAAA==.',
Me='Medie:BAABLgAECn85AAMRAAkJzyD5BgDdAgARAAkJzyD5BgDdAgAWAAQJ4wvYUgCQAAAAAA==.Melody:BAAALgADCgcJDAAAAA==.',
Mi='Michelle:BAABLgAECn8rAAMUAAkJ+xwSGgCJAgAUAAkJ+xwSGgCJAgAHAAgJWhLgLgDHAQAAAA==.Mipzy:BAAALgAECgYJCgAAAA==.',
Mo='Mordolm:BAAALgADCgMJBAAAAA==.',
Na='Naji:BAAALgADCgYJBgABLgAFFAUJHgAUABImAA==.Najinsky:BAACLgAFFH8eAAIUAAUJEiYZCwC7AQAUAAUJEiYZCwC7AQAuAAQKfzIAAhQACQlFJagDAJYDABQACQlFJagDAJYDAAAA.Naurwen:BAAALgADCgIJAwAAAA==.',
Ne='Neesa:BAAALgAECgcJBwABLgAECgkJKQAWAIgZAA==.Neikko:BAAALgAECgUJBQAAAA==.Neilïos:BAAALgADCgMJAwAAAA==.Nellir:BAABLgAECn8zAAMQAAkJWxWqBQD4AQAQAAkJWxWqBQD4AQAjAAMJUwIhEAE+AAAAAA==.Nerestrin:BAAALgAECgMJBAAAAA==.',
Ni='Nitefall:BAAALgAECgUJBQAAAA==.',
No='Norlert:BAAALgAECgQJCAAAAA==.Nosfinariel:BAABLgAECn8ZAAIEAAYJJhddOQCOAQAEAAYJJhddOQCOAQAAAA==.Noxadin:BAAALgAECgUJBQAAAA==.Noxen:BAAALgAECgYJCwAAAA==.',
Ny='Nylorn:BAAALgAECgIJAgAAAA==.',
['Nä']='Nämeless:BAAALgAECgkJAwAAAA==.',
Pa='Pastrami:BAAALgADCgIJAgAAAA==.',
Pi='Pickly:BAAALgAECgYJDAAAAA==.',
Po='Poncho:BAAALgAECgIJCAAAAA==.',
Pr='Proticus:BAAALgAECgYJDAABLgAECggJGQAdAJQTAA==.',
Pu='Pulaski:BAAALgAECgUJBQAAAA==.Punchite:BAAALgAECggJDgABLgAECgkJOgAkACImAA==.',
Ra='Ramarl:BAAALgADCgkJEwABLgAECgkJPQAgAIAgAA==.Raymane:BAAALgAECggJEAAAAA==.',
Re='Reggie:BAAALgAECgQJBAABLgAFFAcJGQAJABgTAA==.Reginato:BAAALgADCgYJBgAAAA==.Rengokuu:BAAALgAECgcJDgAAAA==.Retkrag:BAAALgADCgMJAwABLgAECgkJJgAGAFgiAA==.Revenger:BAAALgADCgYJBgAAAA==.Reynardine:BAACLgAFFH8MAAIHAAQJFhgaGAAvAQAHAAQJFhgaGAAvAQAuAAQKfz0AAwcACQkyGdAKALwCAAcACQkyGdAKALwCABQABgnUCYUWAWgAAAAA.',
Rh='Rhau:BAABLgAECn8YAAIlAAYJvR9ZCQAqAgAlAAYJvR9ZCQAqAgAAAA==.Rhÿsand:BAAALgAECgYJBgABLgAECgkJJAAHAOocAA==.',
Ro='Rombo:BAABLgAECn8XAAIiAAYJgRvODwCDAQAiAAYJgRvODwCDAQAAAA==.Rosastrasza:BAAALgADCgMJAwAAAA==.Rosvenir:BAAALgAECgMJAwAAAA==.Rouse:BAAALgADCgYJCQAAAA==.',
Ru='Ruthos:BAAALgAECgQJBwAAAA==.',
Ry='Rykka:BAAALgAECgUJCAAAAA==.Ryukie:BAAALgAECgUJBgAAAA==.',
Sa='Saiden:BAACLgAFFH8JAAIUAAMJdR79PgAKAQAUAAMJdR79PgAKAQAuAAQKfx8AAhQACQm5IC8bAMYCABQACQm5IC8bAMYCAAAA.Sairen:BAAALgADCgEJAQAAAA==.Savall:BAAALgAECgcJDgAAAA==.',
Se='Serenna:BAAALgAECgMJBAAAAA==.Serios:BAAALgAECgIJAwAAAA==.Servatal:BAAALgAECgMJAwAAAA==.',
Sh='Shakewell:BAAALgADCgYJBgABLgAECggJNAAUAM4fAQ==.Sharun:BAAALgAECgYJBgAAAA==.Sharundito:BAAALgAECgQJBwABLgAECgYJBgAmAAAAAA==.Shelob:BAAALgADCgUJBQAAAA==.Shinashin:BAAALgADCgQJBAAAAA==.Shori:BAAALgADCgEJAQAAAA==.Shrekoning:BAAALgAFFAIJAgAAAA==.',
Si='Sidehussy:BAABLgAECn8yAAIKAAkJuR9gAgArAwAKAAkJuR9gAgArAwAAAA==.Sinistra:BAABLgAECn8cAAIjAAkJzhQhMwD0AQAjAAkJzhQhMwD0AQAAAA==.',
Sk='Skythewise:BAAALgAECgEJAQAAAA==.',
So='Soldjin:BAAALgAECgYJEQABLgAFFAQJDQAgAKsFAA==.Soo:BAAALgADCgMJAwAAAA==.Sorinmarkov:BAABLgAECn9IAAIUAAkJ/B6PFACsAgAUAAkJ/B6PFACsAgAAAA==.',
Sp='Spellsong:BAAALgADCgcJBwAAAA==.Sploçk:BAAALgAECgIJAgAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIZAAYJVRuNhAB5AQAZAAYJVRuNhAB5AQABLgAECgcJGgASAKwcAA==.',
St='Stepinstupid:BAAALgADCgEJAQAAAA==.',
Su='Suicidestyle:BAABLgAECn8YAAQlAAgJKA2NEgDzAAAlAAgJKA2NEgDzAAAQAAMJiAZ8JwBUAAAjAAEJhAfWJgEtAAAAAA==.',
Sy='Syehanan:BAAALgAECgEJAQAAAA==.Syllen:BAAALgADCgIJAgAAAA==.Syraevel:BAAALgAECgQJBAAAAA==.Sythurizm:BAAALgADCgcJBwAAAA==.',
Th='Thorfine:BAABLgAECn8iAAMGAAgJqBVxPwAfAQAGAAYJsxRxPwAfAQANAAUJKRWQLQCoAAAAAA==.',
Ti='Tinymittenz:BAAALgAECgYJEQAAAA==.Tippietoe:BAAALgAECgQJCAAAAA==.',
To='Toryn:BAAALgAECgEJAQAAAA==.Touraine:BAABLgAECn8jAAIfAAgJvh2MDgBgAgAfAAgJvh2MDgBgAgAAAA==.',
Tr='Trashydps:BAAALgADCgIJAgAAAA==.Traxidrag:BAAALgAECgYJDgAAAA==.',
Tu='Tuii:BAAALgADCgcJBwAAAA==.Turien:BAAALgAECgEJAgAAAA==.',
Un='Unmei:BAABLgAECn8wAAIfAAkJCAsULwBXAQAfAAkJCAsULwBXAQAAAA==.',
Va='Valcoree:BAAALgAECgMJAwABLgAECggJHwAWAOsNAA==.Valynor:BAAALgADCgYJBgAAAA==.',
Ve='Vendle:BAABLgAECn8ZAAISAAgJByIrCQABAwASAAgJByIrCQABAwAAAA==.Vesendra:BAAALgADCgYJBgAAAA==.',
Vi='Vinil:BAAALgAECgMJBQAAAA==.',
Vo='Vorastrix:BAAALgAECgEJAgAAAA==.Vox:BAAALgADCgcJAQAAAA==.',
['Vä']='Väsh:BAAALgADCgkJGwAAAA==.',
Wa='Waivern:BAABLgAECn8kAAIHAAkJ6hynDACgAgAHAAkJ6hynDACgAgAAAA==.',
Wh='Whirrlytusk:BAABLgAECn8UAAIbAAcJ3RTPIQClAQAbAAcJ3RTPIQClAQAAAA==.',
Wi='Wibwobb:BAAALgADCgEJAQABLgAECgkJPAAXABsbAA==.Windrunners:BAAALgAECgEJAgAAAA==.',
Wo='Wooly:BAAALgAECgYJBgAAAA==.',
['Wï']='Wïrbelwïnd:BAAALgADCgYJCwABLgAECgYJDAAmAAAAAA==.',
Xa='Xalathaz:BAAALgAECgEJAQABLgAFFAIJBAAmAAAAAA==.',
Ya='Yaoi:BAAALgAECgEJAQAAAA==.',
Ye='Yenzemo:BAABLgAECn86AAIkAAkJIiYRAAB7AwAkAAkJIiYRAAB7AwAAAA==.',
Yx='Yxbv:BAAALgAECggJCwAAAA==.',
Za='Zap:BAAALgAECgMJBgAAAA==.Zarin:BAAALgADCgcJBwAAAA==.',
Ze='Zebranjin:BAAALgADCgcJDQAAAA==.Zeldoris:BAABLgAECn89AAIgAAkJgCD4AgDKAgAgAAkJgCD4AgDKAgAAAA==.Zenelf:BAAALgAECgUJBgABLgAECggJGQAdAJQTAA==.',
Zi='Zillika:BAAALgAECgUJBgAAAA==.',
Zu='Zuk:BAAALgADCgMJAwAAAA==.Zula:BAAALgAECgEJAwAAAA==.Zusumiya:BAAALgADCgcJBwAAAA==.',
['Ém']='Émaeel:BAAALgAECgcJBwABLgAECggJHAAbAKkQAA==.',
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
