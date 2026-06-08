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

local lookup = {'Paladin-Retribution','Priest-Shadow','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Unknown-Unknown','Druid-Guardian','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Paladin-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aahhotep:BAAALgADCgYJDQAAAA==.',
Ab='Abelresurekt:BAABLgAECn8rAAIBAAkJ+g14ZACcAQABAAkJ+g14ZACcAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgEJAQAAAA==.',
Ae='Aellemman:BAAALgAECgIJAgAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QLNXACVAAACAAYJ3QLNXACVAAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn81AAIBAAkJyQ+MYwCeAQABAAkJyQ+MYwCeAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgQJBAAAAA==.Ambitions:BAABLgAECn8fAAIDAAkJdh2/AQDXAgADAAkJdh2/AQDXAgAAAA==.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgADCgIJAgAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCWGAQBcAwAEAAkJxCWGAQBcAwAAAA==.Aranrùth:BAAALgAFFAEJAQAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgIJAgAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8nAAMFAAkJ7Rw6GAB8AgAFAAgJ3Rs6GAB8AgAGAAgJpxqcFgAkAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAnvgwALAQAHAAgJEAnvgwALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAECgYJCgAAAA==.Ashmor:BAAALgADCgkJCQAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxSODABlAQAIAAcJLhWODABlAQAJAAgJ9gyIcABUAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8qAAILAAkJghbJDQCFAgALAAkJghbJDQCFAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAMAAAAAA==.Avarice:BAABLgAECn8kAAINAAkJZBXoDQDzAQANAAkJZBXoDQDzAQAAAA==.',
Aw='Awesomé:BAAALgADCgcJCgABLgAFFAMJBQALAMcDAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgEJAQAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagoHLgCRAQAOAAkJagoHLgCRAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8JAAIPAAQJABTNUAA6AQAPAAQJABTNUAA6AQAuAAQKfzAAAg8ACQkgIQ4YAMICAA8ACQkgIQ4YAMICAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxI1LADBAAAQAAMJNxI1LADBAAAuAAQKfzIABBAACAkbHTERAEUCABAACAkbHTERAEUCAA0AAgnwEZNKAGkAABEAAwmAAgnSAC0AAAAA.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJGwASAAwgAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIEAAYJ2geTWAChAAAEAAYJ2geTWAChAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJCgABAMsKAA==.Bloodegg:BAACLgAFFH8JAAITAAMJvgp5YADMAAATAAMJvgp5YADMAAAuAAQKfzAAAhMACQkXFN9AANQBABMACQkXFN9AANQBAAAA.',
Bo='Boinky:BAABLgAECn8kAAMRAAgJjSVtCAApAwARAAgJjSVtCAApAwAQAAEJ9AZTjwApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gwsTwACAQAOAAYJ8gwsTwACAQAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJGwASAAwgAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8bAAIUAAYJfRJzBwAmAQAUAAYJfRJzBwAmAQAAAA==.',
Bs='Bshoottu:BAABLgAECn8uAAITAAgJnAwdXQCCAQATAAgJnAwdXQCCAQAAAA==.',
Bu='Bubzee:BAAALgAECgkJEAAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Ch='Chawn:BAABLgAECn8tAAISAAkJ4RpSBwClAgASAAkJ4RpSBwClAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8eAAMVAAgJsRViUgDFAQAVAAgJWRRiUgDFAQAWAAYJ7hEkLADvAAAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAcJFAALABwPAA==.Daeheals:BAABLgAFFH8UAAMLAAcJHA/CDwD6AQALAAcJHA/CDwD6AQACAAIJhQsILgB7AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAcJFAALABwPAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAcJFAALABwPAA==.Daethknight:BAAALgADCgIJAgABLgAFFAcJFAALABwPAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJAgAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA6zKgB1AQACAAgJiA6zKgB1AQALAAUJnxCUMAAbAQAXAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAABLgAFFH8FAAIVAAMJrgzasQCmAAAVAAMJrgzasQCmAAAAAA==.Deathbynade:BAABLgAECn8nAAIBAAkJDBJ6UwDEAQABAAkJDBJ6UwDEAQAAAA==.Deathclaw:BAABLgAECn8tAAIJAAcJ2hhSZACeAQAJAAcJ2hhSZACeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Decimatin:BAAALgAECgcJEQABLgAFFAMJCgAQADcSAA==.Deldúwath:BAABLgAECn8xAAIYAAkJfhoiAwBtAgAYAAkJfhoiAwBtAgAAAA==.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAGAMoSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAMJCgAQADcSAA==.',
Di='Dionus:BAABLgAECn8yAAIBAAkJNAxIawCNAQABAAkJNAxIawCNAQAAAA==.',
Dk='Dkragg:BAAALgAECgMJCwABLgAFFAYJDwAGAMoSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn80AAIOAAgJMAO0YQDFAAAOAAgJMAO0YQDFAAAAAA==.Dorkfish:BAAALgAECgIJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn80AAILAAgJexuzEQBNAgALAAgJexuzEQBNAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn89AAIJAAkJrBVlKgAqAgAJAAkJrBVlKgAqAgAAAA==.',
El='Elemetzy:BAAALgAECgUJDQAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgAECgQJBAAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAMAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxrqPgD/AQABAAgJVxrqPgD/AQAAAA==.Fattaco:BAAALgAFFAIJAwABLgAFFAMJCgABAMsKAA==.',
Fe='Feederr:BAABLgAECn8qAAIHAAgJchKwYwBUAQAHAAgJchKwYwBUAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgcJCAAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDAAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8HAAIZAAIJLSRNDQDPAAAZAAIJLSRNDQDPAAAuAAQKfzQAAhkACQnoIo4BACQDABkACQnoIo4BACQDAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBAAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBihbwCVAQAPAAcJXBihbwCVAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8FAAMQAAMJwgkBMQCnAAAQAAMJwgkBMQCnAAARAAIJhgInXgBVAAABLgAFFAYJDwAGAMoSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgcJCAAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAECggJDwAAAA==.',
Gr='Graebeard:BAABLgAECn8XAAIVAAcJXwtQyQDnAAAVAAcJXwtQyQDnAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIZAAkJziWaAABqAwAZAAkJziWaAABqAwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8pAAIFAAgJvx6UFQCSAgAFAAgJvx6UFQCSAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8oAAIHAAkJuA9xRgCnAQAHAAkJuA9xRgCnAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn81AAMZAAkJsxzHBwBGAgAZAAgJrxvHBwBGAgARAAYJZwVKfQC3AAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8dAAIHAAgJxRZYCgBOAgAHAAgJxRZYCgBOAgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgQJCgAAAA==.',
In='Inkarok:BAABLgAECn8zAAIaAAkJshXPEAALAgAaAAkJshXPEAALAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgkJGQAWAAkjAA==.',
Is='Ishkode:BAABLgAECn8bAAIKAAgJNgWQFQALAQAKAAgJNgWQFQALAQAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8YAAIGAAYJNBudDAC6AQAGAAYJNBudDAC6AQAuAAQKfyYAAwYACAlHHxINAM4CAAYACAlHHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJhqJTADXAQABAAcJJhqJTADXAQAbAAMJKgiqOwBiAAAAAA==.',
Ka='Kadriel:BAAALgAECgYJCwAAAA==.Kalanrahl:BAACLgAFFH8FAAIPAAUJ7AMwcQDvAAAPAAUJ7AMwcQDvAAAuAAQKfzIAAg8ACQlfFyktAF4CAA8ACQlfFyktAF4CAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgcJDgAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIXAAcJoQamPQDsAAAXAAcJoQamPQDsAAAAAA==.',
Kh='Khaiduus:BAABLgAECn8yAAIGAAkJ5Rp3EgBPAgAGAAkJ5Rp3EgBPAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIcAAkJfx+9AgC8AgAcAAkJfx+9AgC8AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgADCgcJBwAAAA==.Kottenmouth:BAACLgAFFH8XAAISAAUJrB4uCwBeAQASAAUJrB4uCwBeAQAuAAQKfzwAAhIACQlQJbEBAD0DABIACQlQJbEBAD0DAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAACLgAFFH8IAAIdAAMJxA/qJADqAAAdAAMJxA/qJADqAAAuAAQKfzkAAx0ACQkJHIIKAHACAB0ACQkJHIIKAHACAAMABAm5EZkWALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAECgMJAwAAAA==.',
Le='Lebron:BAABLgAECn8xAAIOAAgJ3R7hDgB/AgAOAAgJ3R7hDgB/AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJFAAAAA==.Lizardmann:BAABLgAECn8dAAIeAAgJgxeqHwDTAQAeAAgJgxeqHwDTAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIfAAYJtAz0GADdAAAfAAYJtAz0GADdAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgEJAQAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8sAAIPAAkJfQ6YWADNAQAPAAkJfQ6YWADNAQAAAA==.Maryla:BAACLgAFFH8KAAIBAAMJywrAagDJAAABAAMJywrAagDJAAAuAAQKfzkAAgEACQk1HfAjAGsCAAEACQk1HfAjAGsCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJEAAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAAALgAFFAMJBAAAAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgQJCgAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8yAAQgAAkJPhMaJgDdAQAgAAkJPhMaJgDdAQAhAAYJjBzbJgBwAQAEAAYJOAymRgDYAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgMJAwABLgAECgkJGQAWAAkjAA==.Nativelock:BAABLgAECn8zAAIKAAgJ/QaHEwAjAQAKAAgJ/QaHEwAjAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRW+HQD6AQAOAAkJaRW+HQD6AQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgADCgUJCAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8bAAISAAUJDCC8GgDDAQASAAUJDCC8GgDDAQAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn8yAAMXAAkJ8BPDGAD5AQAXAAkJ8BPDGAD5AQACAAEJtQKKjwAfAAAAAA==.Nyzen:BAAALgADCgUJBQAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxMZIQDNAQAGAAkJdxMZIQDNAQAFAAcJdBTXLwDIAQABLgAFFAMJBgAeAF8FAA==.Onthecoda:BAACLgAFFH8KAAIRAAQJbRD8LAD5AAARAAQJbRD8LAD5AAAuAAQKfyMAAxEACQnDGf4SAKsCABEACQnDGf4SAKsCABAACQnKDYgkAJkBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8rAAIiAAgJiB99BADbAgAiAAgJiB99BADbAgAAAA==.',
Pa='Paigeturner:BAABLgAECn8/AAMPAAkJkw45VgDTAQAPAAkJkw45VgDTAQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgcJCAAMAAAAAA==.Papalock:BAAALgAFFAEJAgAAAA==.',
Pe='Persymphony:BAABLgAECn9CAAIJAAgJcSBdGwB7AgAJAAgJcSBdGwB7AgAAAA==.',
Ph='Phabio:BAABLgAECn8cAAIBAAkJMBB9UgDHAQABAAkJMBB9UgDHAQAAAA==.Phlorps:BAABLgAFFH8NAAQQAAUJvRBmIQADAQAQAAQJvRBmIQADAQANAAQJGQTpHQCRAAARAAEJ/wK8aAA5AAAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAAALgAECgcJDAAAAA==.Pinkee:BAAALgAECgEJAgAAAA==.Pinklock:BAAALgADCggJDgABLgAECgcJCAAMAAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBnTHgBLAgAFAAgJkBnTHgBLAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJAgAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQdArgAWAQABAAgJKQdArgAWAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8RAAIVAAUJlB5HQgBeAQAVAAUJlB5HQgBeAQAuAAQKfyIAAhUACQmCHwIOACsDABUACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgADCgYJBgABLgAECgkJOgATAB0eAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAGAMoSAA==.Ragnatotemzz:BAABLgAFFH8PAAIGAAYJyhKuFQBXAQAGAAYJyhKuFQBXAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgUJEQAAAA==.',
Re='Rebelchild:BAAALgAECgEJAQABLgAECgUJDQAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgUJDQAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgUJDQAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Renkari:BAAALgAECgQJBQAAAA==.Rennl:BAABLgAECn8kAAIBAAcJ3xVGagCPAQABAAcJ3xVGagCPAQAAAA==.Requiemechoe:BAACLgAFFH8IAAMjAAQJ8hWECgAxAQAjAAQJPRWECgAxAQAVAAEJHxQw+ABFAAAuAAQKfxYABCMABgnXH2UNAI4BACMABQmPIWUNAI4BABUABQmhG6yXADABABYAAQnBDg5ZAC8AAAEuAAUUBQkiAAsAISEA.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgADCgIJAQAAAA==.Rhutuuzy:BAAALgAECgUJDQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgcJCAAAAA==.Ripsets:BAACLgAFFH8XAAMTAAUJuyatEAC1AQATAAUJuyatEAC1AQAfAAEJxyJUIwBjAAAuAAQKfzQAAxMACQmwJVEVAJ4CAB8ACAlJIH8QALgCABMACAmoJVEVAJ4CAAAA.',
Ro='Roflkopterz:BAABLgAECn8eAAITAAgJBRqzPADiAQATAAgJBRqzPADiAQAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgYJBgAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAECgEJAQABLgAFFAEJAgAMAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAGAMoSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIVAAkJvB7IFwCwAgAVAAkJvB7IFwCwAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFQAAAA==.Sarigos:BAABLgAECn8hAAMiAAgJIxYxDAALAgAiAAgJIxYxDAALAgAkAAEJXxHwIABCAAAAAA==.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgcJCAAMAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8UAAMaAAQJ+w6QGADAAAAHAAMJSA6pXgDBAAAaAAMJ7gyQGADAAAAuAAQKf0IAAwcACQneH9wiADsCAAcACAk7H9wiADsCABoACQnWFcYVAMsBAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9CAAIWAAgJQx+ZCwBLAgAWAAgJQx+ZCwBLAgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpASUxwC5AAAJAAYJpASUxwC5AAAAAA==.Shadyladye:BAAALgADCgkJCQAAAA==.Shariandel:BAABLgAECn8XAAIFAAgJaBliKgAEAgAFAAgJaBliKgAEAgABLgAECggJIwAVAC8bAA==.Sharrin:BAABLgAECn8uAAINAAkJOiHpAgD1AgANAAkJOiHpAgD1AgAAAA==.Shiebert:BAABLgAECn8ZAAIGAAcJnwxZSAACAQAGAAcJnwxZSAACAQAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAGAMoSAA==.Shrodwrah:BAABLgAECn8yAAIXAAkJBAtMLABbAQAXAAkJBAtMLABbAQAAAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIJAAkJZQbZcwBNAQAJAAkJZQbZcwBNAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgQJCAAAAA==.',
So='Solomoon:BAACLgAFFH8iAAILAAUJISF8EgDSAQALAAUJISF8EgDSAQAuAAQKfycABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAIABAmiHvU+AP4AABcAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCgAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECggJNAALAHsbAA==.',
St='Stabsrael:BAABLgAFFH8cAAIdAAUJDSELFQBUAQAdAAUJDSELFQBUAQAAAA==.Stalkurnjr:BAAALgAECgMJAwABLgAECgkJIQAiACMWAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAZALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIlAAkJ/x18CQBSAgAlAAkJ/x18CQBSAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgYJEwAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn8vAAITAAgJiQ86UgCfAQATAAgJiQ86UgCfAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBmHDQB2AgACAAkJwBmHDQB2AgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8xAAIfAAgJvBddCADsAQAfAAgJvBddCADsAQAAAA==.',
Th='Theelderlord:BAAALgAECgMJAwABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIVAAMJIiSGcAASAQAVAAMJIiSGcAASAQAuAAQKf0MAAhUACAmlJIYRANkCABUACAmlJIYRANkCAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tillandra:BAABLgAECn8aAAIXAAgJyBHRIACvAQAXAAgJyBHRIACvAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJHQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAEJAgAMAAAAAA==.',
Tw='Twistedteas:BAABLgAECn8gAAIHAAkJtAmEYABcAQAHAAkJtAmEYABcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8GAAIBAAIJAiJVbwDAAAABAAIJAiJVbwDAAAAuAAQKfykAAwEACQk4IhMbAJgCAAEACQk4IhMbAJgCACYAAQl6AQabABwAAAAA.',
Um='Umbralstar:BAABLgAECn8gAAQXAAkJ0hwcDACXAgAXAAgJBR8cDACXAgACAAMJVAu3WQChAAALAAEJQQ7ccgAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIVAAcJ9xZ8fQBfAQAVAAcJ9xZ8fQBfAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAISAAkJByP5AgAJAwASAAkJByP5AgAJAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8eAAMBAAkJkQ7GWgCyAQABAAkJkQ7GWgCyAQAmAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8hAAMEAAgJkRnYGwDDAQAEAAgJRBnYGwDDAQAhAAcJERPxKABjAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMTAAkJWRDlQgDNAQATAAkJWRDlQgDNAQAfAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8oAAIIAAgJURH6CwBxAQAIAAgJURH6CwBxAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMGAAkJhyEHBwDhAgAGAAkJESEHBwDhAgAnAAcJWBuvDADYAQABLgAECggJLAAiAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9BAAIUAAgJVhKIBACfAQAUAAgJVhKIBACfAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAUJIgALACEhAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAABLgAECn86AAITAAkJHR72FACgAgATAAkJHR72FACgAgAAAA==.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8uAAIHAAgJjBIlTwCMAQAHAAgJjBIlTwCMAQAAAA==.',
Za='Zaaren:BAEALgADCgUJBQABLgAECgkJGQAWAAkjAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9gjIMwA8AQAQAAkJ9gjIMwA8AQARAAQJ5AhcmQB0AAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEBLgAECn8ZAAMWAAkJCSM3DgAbAgAWAAkJCSM3DgAbAgAVAAMJUwZKGgF4AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAFFAEJAQABLgAFFAUJEQAVAJQeAA==.Zeromus:BAABLgAECn81AAIjAAkJWApeDwBuAQAjAAkJWApeDwBuAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh3ZGAD4AQACAAcJDh3ZGAD4AQABLgAFFAIJBgABAAIiAA==.',
['Zÿ']='Zÿrä:BAAALgAECgcJBwAAAA==.',
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
