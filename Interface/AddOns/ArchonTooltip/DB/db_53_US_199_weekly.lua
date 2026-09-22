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

local lookup = {'Warrior-Fury','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Mage-Fire','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','Mage-Arcane','Warrior-Protection','Hunter-Survival','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker','Priest-Holy','DemonHunter-Vengeance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Mage-Frost','Druid-Restoration',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aabbigale:BAAANQADCgIIAgAAAA==.',
Ab='Abigt:BAAANQADCgIJAQAAAA==.',
Ad='Adalaidê:BAAANQADCgQIBQAAAA==.',
Ae='Aerynne:BAAANQADCgYJCwAAAA==.',
Ai='Airie:BAAANQAECgUICQAAAA==.',
Ak='Akuso:BAAANQADCgIIAgAAAA==.',
Al='Alcohaulorc:BAAANQAECgQIAwAAAA==.Alert:BAAANQAECgEIAQAAAA==.Aloris:BAAANQAECgQICAAAAA==.Aloy:BAAANQAFFAIIAgAAAA==.Aluhx:BAAANQADCgYJCgABNQAECggJFwABAIUfAA==.',
Am='Amednato:BAAANQAECgUJCgAAAA==.',
An='Anaeli:BAAANQAECgYIEwAAAA==.Anastarian:BAAANQAECgEJAQAAAA==.Ancalagonn:BAABNQAECoEOAAMCAAYKggigGwAtAQACAAYKggigGwAtAQADAAMKVgMBFABmAAAAAA==.Angita:BAAANQADCggIHAAAAA==.Annaris:BAACNQAFFIEIAAIEAAQK9x72AwCGAQAEAAQK9x72AwCGAQA1AAQKgSIAAwQACQruJF8DALIDAAQACQruJF8DALIDAAUACAruGPEeAPEBAAAA.Antipæn:BAEBNQAECoEoAAMGAAkKuiXnAgDXAwAGAAkKuiXnAgDXAwAHAAkKOSGKBgBvAwAAAA==.',
Ap='Apologia:BAAANQAECgUIBwAAAA==.',
Aq='Aquaphobic:BAAANQAECgEIAQAAAA==.',
Ar='Arcanoth:BAAANQADCgIIAgAAAA==.Archaeolight:BAAANQADCgQIBAABNQAECgYIBgAIAAAAAA==.Ares:BAABNQAECoEZAAIJAAkKhCQUCgCKAwAJAAkKhCQUCgCKAwAAAA==.Armorgorden:BAAANQAECgYJEAAAAA==.Aroviaa:BAAANQAECgYIDwAAAA==.Arpmek:BAAANQAECgYJEAAAAA==.',
As='Asharienne:BAAANQAECgYJCAAAAA==.Ashlynne:BAAANQAECgYJCwAAAA==.',
Au='Audiobully:BAAANQADCgUIBgABNQAECgYJDAAIAAAAAA==.Auralynn:BAAANQAECgQJBAABNQAECgYJCwAIAAAAAA==.Auriella:BAAANQADCgcICQAAAA==.Aurtt:BAAANQAECgYIDAAAAA==.',
['Aö']='Aöb:BAAANQADCgQIBgAAAA==.',
Ba='Bahahaknight:BAAANQAECgUICgAAAA==.Bahree:BAAANQADCgIIAgAAAA==.Bakhar:BAAANQAECgUJCAAAAA==.Balora:BAAANQADCgcJCwAAAA==.Barnette:BAABNQAECoEcAAIKAAgKYw6RAQAdAgAKAAgKYw6RAQAdAgAAAA==.Basyleus:BAAANQADCgEIAQAAAA==.',
Be='Belthos:BAAANQAECgYICwAAAA==.Benihime:BAAANQAECgEIAQAAAA==.Berristan:BAABNQAECoEgAAIHAAkKtwyGOgAOAgAHAAkKtwyGOgAOAgAAAA==.',
Bi='Bigdawgsteve:BAAANQADCgIIAgAAAA==.Bigmarv:BAAANQAECgUICQAAAA==.Bittytigs:BAABNQAECoEoAAMLAAkKOhxMGQDAAgALAAkKOhxMGQDAAgAMAAEKNgZN7AApAAAAAA==.',
Bl='Bluewitchpa:BAAANQADCgUIEgAAAA==.Blumangood:BAAANQAECgYIEQAAAA==.',
Bo='Bollux:BAAANQAECgEIAgAAAA==.Bosc:BAAANQAECgUJCwAAAA==.Boudiicca:BAAANQADCgYJCwAAAA==.Boxmasterr:BAAANQAECgYIDwAAAA==.',
Br='Braagh:BAAANQABCggICwAAAA==.Brasmir:BAAANQAECgYIDAAAAA==.Brianzero:BAAANQABCgQJBgAAAA==.Brinotriage:BAAANQABCgIIAgAAAA==.',
Bu='Bubblemoth:BAAANQADCgMIBAABNQAECgUJCgAIAAAAAA==.Buik:BAAANQADCgYICQAAAA==.Bulge:BAAANQAECgUICgABNQAECggIHwANAIYYAA==.Bulgogi:BAABNQAECoEfAAINAAgKhhhyIQBYAgANAAgKhhhyIQBYAgAAAA==.',
['Bö']='Börk:BAAANQADCggIHAAAAA==.',
Ca='Capy:BAAANQAECgIJAgABNQAECgkJIgAOALgdAA==.Cardran:BAAANQADCgIIAgABNQAECgUJCgAIAAAAAA==.Cayda:BAAANQADCgYJCQAAAA==.Caylara:BAAANQADCgcIGQAAAA==.Cayssaber:BAAANQADCggIDAAAAA==.',
Ce='Celrythis:BAAANQADCgcIGAAAAA==.',
Ch='Chai:BAAANQAECgUICAAAAA==.Chaintrain:BAAANQAECgMIAwABNQAECgMJBgAIAAAAAA==.Chellyy:BAAANQADCggIGAABNQADCggIIQAIAAAAAA==.',
Ci='Cinia:BAAANQADCgYIBgABNQAFFAIIAwAIAAAAAA==.',
Co='Coralbubbles:BAAANQAECgUIBQAAAA==.Coralorchid:BAAANQAECgEIAQAAAA==.Coralrages:BAAANQAECgMIBgAAAA==.',
Cr='Cromenockle:BAAANQAECgcIDQAAAA==.',
Cu='Curissan:BAAANQAECgEIAQAAAA==.',
['Cø']='Cøndemn:BAAANQAECggJBgAAAA==.',
Da='Dalgon:BAAANQAFFAIJAgABNQAECgkJIAAHAC0ZAA==.Dalir:BAAANQADCgcIEAAAAA==.Dalspin:BAAANQADCgYIDAABNQAECgkJIAAHAC0ZAA==.Dalthepal:BAABNQAECoEgAAIHAAkKLRmCGADLAgAHAAkKLRmCGADLAgAAAA==.Damné:BAAANQAECgYIDwABNQAECggJGgAJAN8QAA==.Davidline:BAAANQAECgcICwAAAA==.',
De='Deadish:BAAANQAECgUIDAAAAA==.Deathsaberss:BAABNQAECoEgAAMJAAgKKxf5SABFAgAJAAgKKxf5SABFAgAPAAMKlAutIQCSAAAAAA==.Deathvex:BAAANQAECgQJBgABNQAECggJHgAQACwcAA==.Deight:BAAANQADCgIIAgAAAA==.Dejamoo:BAAANQADCgYJCwAAAA==.Dendahn:BAAANQAECgcIDQAAAA==.Destinee:BAAANQAECgQJCwAAAA==.',
Di='Diladrin:BAABNQAECoEfAAIRAAkKeBdiBwBlAgARAAkKeBdiBwBlAgAAAA==.Dinomight:BAAANQADCgQIBAAAAA==.',
Do='Doileag:BAAANQAECgIJAgAAAA==.Doomgrave:BAAANQADCgEIAQAAAA==.Dottmatrix:BAAANQADCgcJHgAAAA==.Doubledowns:BAAANQADCgMIBAAAAA==.',
Dr='Dreadwing:BAAANQADCgYJCwAAAA==.Druromu:BAAANQADCgcIFgAAAA==.',
Du='Dufs:BAABNQAECoEbAAILAAkKQSBQDgAWAwALAAkKQSBQDgAWAwAAAA==.Dunkan:BAAANQADCgYICwAAAA==.Dustbunny:BAAANQAECgYIDwAAAA==.',
Dw='Dwagon:BAAANQAECgYJDAAAAA==.',
Dy='Dylsonlolqt:BAAANQADCgUICAAAAA==.',
['Dã']='Dãrling:BAAANQABCgEIAQAAAA==.',
['Dû']='Dûn:BAABNQAECoEeAAMSAAkK0R1cBQCqAgASAAgK1B1cBQCqAgATAAQKexX9KwAJAQAAAA==.Dûna:BAAANQAECggIEwABNQAECgkJHgASANEdAA==.',
El='Elaatia:BAAANQAECgYIDwAAAA==.Elidria:BAAANQABCgIIAgABNQADCgYIBgAIAAAAAA==.Ellysprocket:BAAANQADCgUJCQAAAA==.Elrric:BAAANQADCgcICgAAAA==.Elyak:BAAANQADCgIIAgAAAA==.',
En='Envoy:BAAANQADCgYIDAAAAA==.',
Er='Erakron:BAAANQAECgQJCgAAAA==.Erine:BAAANQAECgIIAgAAAA==.Erouvi:BAAANQADCgIIAgABNQAECgYIDwAIAAAAAA==.Eroviaa:BAAANQADCgEIAQABNQAECgYIDwAIAAAAAA==.',
Ez='Ezothen:BAAANQAECgEIAQAAAA==.',
Fa='Facelessman:BAAANQABCggJEQAAAA==.Faedoria:BAAANQADCgcJGAAAAA==.Faeryln:BAABNQAECoEYAAIUAAgK/QU7WgBvAQAUAAgK/QU7WgBvAQAAAA==.Fatalcheese:BAAANQABCgQIBAAAAA==.Faustus:BAAANQAECgYJBgAAAA==.',
Fe='Felyyia:BAAANQADCgcIBwABNQAFFAQJCAAEAPceAA==.',
Fi='Fiddlestix:BAAANQAECgQIBAAAAA==.Firebrande:BAAANQADCggIHAAAAA==.Fisticuffs:BAAANQADCgUIEAAAAA==.Fizcrankshot:BAAANQAECgcIEwAAAA==.',
Fl='Flamewhisker:BAAANQADCggIHAAAAQ==.',
Fr='Fraublucher:BAAANQAECgUJCwAAAA==.Frewyn:BAAANQADCgcJDQAAAA==.Frostimoth:BAAANQAECgUJCgAAAA==.Frozty:BAAANQAECgEJAgAAAA==.',
Ga='Galandel:BAAANQADCgUIEgAAAA==.Galial:BAABNQAECoEjAAIVAAkK/BihAwCnAgAVAAkK/BihAwCnAgAAAA==.Gantar:BAAANQAECgEIAQABNQAECggIGQAWAA4jAA==.Garradin:BAAANQADCgEIAQAAAA==.Garrunter:BAAANQADCggIFgAAAA==.Gaznol:BAAANQADCgQIBAABNQAECgUJCgAIAAAAAA==.',
Ge='Gelasera:BAAANQADCggIHAAAAA==.Gemitra:BAAANQADCgcIBwABNQAECgEIAQAIAAAAAA==.Geneth:BAAANQAECgUIBQAAAA==.George:BAABNQAECoEUAAIJAAcKlxw6UgAjAgAJAAcKlxw6UgAjAgAAAA==.',
Gh='Ghalta:BAAANQADCgIIAgABNQAECgYJDAAIAAAAAA==.Ghrol:BAAANQABCgYJBgABNQAECgYJEgAIAAAAAA==.',
Gl='Glaivethras:BAABNQAECoEYAAIVAAgKYx2tAwCkAgAVAAgKYx2tAwCkAgAAAA==.Glenfin:BAAANQADCgQIBgAAAA==.',
Gr='Gremlynn:BAAANQADCggICAAAAA==.Grimclaw:BAAANQAFFAMIAwAAAA==.Groot:BAAANQAECgQJBAABNQAECgUJCAAIAAAAAA==.',
Gu='Guthrek:BAAANQAECgIIAQAAAA==.',
Ha='Hamfist:BAAANQADCgIIAgABNQAECggJDAAIAAAAAA==.Hannebal:BAAANQAECgcIEAAAAA==.',
He='Healyclam:BAAANQADCgMIAwAAAA==.Heynow:BAAANQADCgUICQAAAA==.',
Hi='Highmountain:BAAANQADCgYICwAAAA==.Hilimed:BAABNQAECoEYAAIXAAgKjAqQYQCkAQAXAAgKjAqQYQCkAQAAAA==.',
Ho='Hobs:BAAANQABCgMIAwAAAA==.Hoosier:BAAANQADCgUIBQAAAA==.',
Hu='Huasca:BAAANQADCgUIBQAAAA==.Huthuel:BAAANQABCggIFAAAAA==.',
Hy='Hydra:BAAANQADCgYIBgABNQAECgYJDwAIAAAAAA==.Hyve:BAAANQADCgcIDAABNQAECgYIEQAIAAAAAA==.',
['Hà']='Hàney:BAEANQAECgQIBAAAAA==.',
['Hé']='Hélio:BAAANQADCgUIBQAAAA==.',
Ia='Ia:BAAANQAECgcJEgAAAA==.',
Id='Idontsuck:BAAANQADCggICwAAAA==.',
Il='Ilieau:BAAANQAECgEIAQAAAA==.Illida:BAAANQADCgYIBgAAAA==.',
Im='Imamalelol:BAAANQAECgIIAgAAAA==.',
In='Inarrah:BAAANQADCgEIAQAAAA==.Intrepidhero:BAAANQADCgEIAQAAAA==.',
Ir='Irkenfox:BAEBNQAECoEcAAIPAAkKFyH0AQBiAwAPAAkKFyH0AQBiAwAAAA==.',
It='Ithran:BAAANQADCgUIBQAAAA==.',
Iw='Iwilltank:BAAANQADCgYICwAAAA==.',
Ix='Ixitt:BAAANQAECgYIDwAAAA==.',
Ja='Jama:BAAANQADCgYIBgAAAA==.Janderick:BAAANQAECgUJCAAAAA==.',
Je='Jellacee:BAAANQADCgYJCwAAAA==.',
Ji='Jimboberjim:BAABNQAECoEgAAIYAAkKzSLyAACKAwAYAAkKzSLyAACKAwAAAA==.Jiminie:BAAANQAECgYIDAAAAA==.',
Jo='Jolio:BAAANQAECgMJBgAAAA==.Joltraxi:BAAANQABCgMIAwABNQAECgMJBgAIAAAAAA==.Joshie:BAABNQAECoEZAAIWAAgKDiOwCwAgAwAWAAgKDiOwCwAgAwAAAA==.Joshy:BAAANQADCgcIBwABNQAECggIGQAWAA4jAA==.',
Ju='Jujubeans:BAAANQAECgEIAQAAAA==.Juniornite:BAAANQAECgYIEAAAAA==.Justthetouch:BAAANQADCggICAAAAA==.',
Jy='Jygglypuff:BAAANQADCgcIBwAAAA==.',
Ka='Kadaan:BAAANQAECgMJAwAAAA==.Kagemaro:BAAANQAECgYJDAAAAA==.Kalimathath:BAAANQADCgYJCQAAAA==.Kalzod:BAABNQAECoEgAAIXAAkKhB7NCwAvAwAXAAkKhB7NCwAvAwAAAA==.Kataki:BAAANQAECgIIAgABNQAECgYJDAAIAAAAAA==.Katia:BAAANQADCgcIGAAAAA==.Kativeria:BAAANQADCggIHAAAAA==.Katjayna:BAAANQADCgUIBQAAAA==.Kaysabr:BAAANQADCgQIBAAAAA==.Kayssaber:BAAANQADCggIGAAAAA==.',
Ke='Kebab:BAAANQAECgQJBAAAAA==.Kelsifer:BAAANQAECgQICwABNQAECgYJBgAIAAAAAA==.Kempra:BAAANQADCgcIBwAAAA==.Kemprei:BAAANQADCgUJBQAAAA==.Kendralust:BAAANQAECgcICAAAAA==.Kerfufle:BAAANQABCgIJAgAAAA==.',
Ki='Killmora:BAAANQADCgUJEgAAAA==.Kippars:BAAANQADCggJFgAAAA==.',
Ko='Kodazoff:BAAANQAECgEIAgAAAA==.Kora:BAAANQABCgEIAgAAAA==.Korevash:BAAANQAECggIEwAAAA==.',
Kr='Krissylu:BAAANQADCgcIEAAAAA==.Krothix:BAAANQAECgUIDQAAAA==.Kryrande:BAAANQADCgQJCwAAAA==.Kryshym:BAAANQAECgMIAgAAAA==.Krythrall:BAAANQADCgUIBQABNQAECgMIAgAIAAAAAA==.',
Ks='Kspectactle:BAAANQADCgMIAwAAAA==.',
Ku='Kuilei:BAAANQADCgYJCwABNQADCgcIDwAIAAAAAA==.Kurorø:BAAANQADCgcIGAAAAA==.',
Ky='Kyrayna:BAAANQADCgUIBwAAAA==.',
La='Ladara:BAAANQAECgYIEQAAAA==.Laima:BAAANQADCgEIAQAAAA==.Lavitz:BAAANQADCgIIAgAAAA==.',
Le='Leheo:BAAANQADCgIIAgAAAA==.Lehua:BAAANQADCgIIAgAAAA==.Leilanii:BAAANQADCgQICQAAAA==.Lemook:BAAANQAECgEIAQAAAA==.Leonìdas:BAAANQADCgYIBgAAAA==.Leð:BAAANQAECggICAAAAA==.',
Li='Licker:BAAANQAECgUICQABNQAECgcIDQAIAAAAAA==.Lightbulb:BAAANQADCgYIDQAAAA==.Lightstormer:BAAANQADCgUIEgAAAA==.Lilamae:BAAANQADCgYIDQAAAA==.Lilarielle:BAAANQAECgUJEAAAAA==.Lildookie:BAAANQADCggICwAAAA==.Liliel:BAAANQADCgMIAwABNQAECgUJCgAIAAAAAA==.Liliela:BAAANQAECgUJCgAAAA==.Lilyannah:BAAANQADCgEIAQAAAA==.Liodragon:BAAANQADCgUIBQABNQAECgYJCAAIAAAAAA==.Lite:BAAANQAECgQIBAAAAA==.Liø:BAAANQAECgYJCAAAAA==.',
Ll='Lluniez:BAAANQAECgUIDAAAAA==.',
Lo='Lockroknroll:BAAANQAECggJDAAAAA==.Losoli:BAAANQAECgYIEQAAAA==.Lotor:BAAANQADCgYIBgAAAA==.Lowchin:BAAANQADCgYICgAAAA==.',
Lu='Lutherion:BAAANQAECgUIDAAAAA==.',
Ly='Lycemmas:BAAANQAECgUJCgAAAA==.',
['Lï']='Lïo:BAAANQADCgYIBwABNQAECgYJCAAIAAAAAA==.',
Ma='Macoun:BAAANQAECgUJCwAAAA==.Magicshowers:BAAANQAECgYIDwAAAA==.Manseed:BAAANQABCgQJBAAAAA==.Maple:BAAANQAECgEIAQAAAA==.Martei:BAABNQAECoEbAAIZAAkKlBvQAwDtAgAZAAkKlBvQAwDtAgAAAA==.Maríneth:BAAANQADCgcIFwAAAA==.Mascara:BAAANQAECgUJBgAAAA==.',
Mi='Midway:BAAANQAECgIIAgAAAA==.Mirokushan:BAAANQADCgYJCwAAAA==.Missfire:BAAANQADCgcIEAAAAA==.Misticlady:BAAANQAECgQIBgAAAA==.Mistrariel:BAAANQADCgMIAwABNQAECgYJDQAIAAAAAA==.Mizukì:BAAANQABCgQJBgAAAA==.',
Mo='Moluubar:BAAANQAECgUIBwAAAA==.Moradin:BAAANQADCgMJAwAAAA==.Mordemour:BAAANQAECgEIAQAAAA==.',
Mu='Mufler:BAAANQABCgQIBQAAAA==.Mushù:BAAANQAECgQIBAABNQAECgYIDAAIAAAAAA==.',
My='Myfire:BAAANQADCgYIBgAAAA==.Myrrh:BAAANQAECgYIDwAAAA==.',
Na='Nalik:BAAANQADCgcIEAAAAA==.Nanou:BAAANQAECgIIAgAAAA==.Nardiaun:BAAANQADCgYIBgAAAA==.Naturebait:BAAANQADCgQIBAABNQAECgYIEQAIAAAAAA==.',
Ne='Nerzheul:BAAANQAECgQJBgAAAA==.',
Ni='Nimravidae:BAAANQAECgUICgAAAA==.Ninelives:BAAANQAECgQIBQAAAA==.Nitecrawler:BAAANQADCgQIBAAAAA==.Niteeye:BAAANQABCgIIAgABNQAECgYIEAAIAAAAAA==.Niteryu:BAAANQAECgEIAgABNQAECgYIEAAIAAAAAA==.',
No='Nolokkotal:BAAANQAECgYJBgABNQAECgYIBgAIAAAAAA==.Nospitfisty:BAAANQADCgQIBAAAAA==.Noxolon:BAAANQAECgMIBAAAAA==.',
Nr='Nreaf:BAABNQAECoEaAAIGAAgKxxLYWgDvAQAGAAgKxxLYWgDvAQAAAA==.',
Oi='Oili:BAABNQAECoEgAAMaAAgKwBjTBABVAgAaAAgKwBjTBABVAgAOAAQK1gtDEwHpAAAAAA==.',
Ol='Olarrick:BAAANQADCgYICwABNQAECgcIFAAJAJccAA==.',
Oo='Oops:BAABNQAECoEfAAIWAAkKOCCbCwAhAwAWAAkKOCCbCwAhAwAAAA==.',
Or='Ornstein:BAAANQADCggJAwAAAA==.',
Ot='Ottuk:BAABNQAECoEjAAINAAkKDB/xCgA3AwANAAkKDB/xCgA3AwAAAA==.',
Pa='Padpaw:BAAANQAECgUJCAAAAA==.Pakraxes:BAAANQAECgYIDwAAAA==.Paksenarrion:BAAANQAECgUICgAAAA==.Palehoof:BAAANQADCgUJCQAAAA==.Pandemônium:BAAANQADCgMIAwABNQAECgYICgAIAAAAAA==.Pandemönium:BAAANQAECgYICgAAAA==.Parts:BAAANQABCgYIBwAAAA==.Patchington:BAAANQADCgcIGAAAAA==.Pañdemönium:BAAANQAECgQJCgABNQAECgYICgAIAAAAAA==.',
Pe='Pepperrjakk:BAAANQADCgEIAQAAAA==.Perrylee:BAAANQAECgMJAwAAAA==.',
Ph='Philia:BAABNQAECoEXAAMJAAgKmRf4XgD1AQAJAAgK2RL4XgD1AQAPAAMKwBzJGQD1AAABNQAFFAIIAgAIAAAAAA==.',
Pi='Pixelme:BAAANQAFFAEJAgAAAA==.',
Pl='Pleggster:BAAANQADCgMIAwAAAA==.',
Po='Pochula:BAAANQAECgUJCAAAAA==.',
Pr='Primo:BAABNQAECoExAAIHAAkKkxOwLgBFAgAHAAkKkxOwLgBFAgAAAA==.Protricity:BAAANQAECgYICgAAAA==.',
Ps='Psychoprowla:BAAANQAECgYIEAAAAA==.Psychozdrood:BAAANQAECgEIAQAAAA==.',
['Pæ']='Pæn:BAEANQADCgcIEAABNQAECgkJKAAGALolAA==.',
Qu='Quantar:BAAANQADCgYIBgABNQADCggIHAAIAAAAAA==.Quickstab:BAAANQAECgQJBAAAAA==.',
Ra='Ragana:BAAANQAECgMIAwAAAA==.Rainger:BAAANQADCgMIAwAAAA==.Rallypaly:BAAANQADCgIIAgAAAA==.Ramthor:BAAANQADCggICAAAAA==.Rancooll:BAAANQADCgUIDQAAAA==.Rasniir:BAAANQAECgcIEQAAAA==.Ravenar:BAAANQAECgQJBAAAAA==.',
Re='Regna:BAABNQAECoEgAAMJAAkK8CUuDAB4AwAJAAkKFCQuDAB4AwABAAQKCiZeCQC6AQAAAA==.Relkon:BAAANQADCgMIAwAAAA==.Remaked:BAACNQAFFIEKAAISAAUKmxKJAQBtAQASAAUKmxKJAQBtAQA1AAQKgSoAAhIACQrdHg4EAOwCABIACQrdHg4EAOwCAAAA.Requinix:BAAANQAECgYIEQAAAA==.Reynmaker:BAAANQADCgQIBAAAAA==.',
Rh='Rhowyn:BAAANQADCgQIBAAAAA==.',
Ri='Riptidez:BAAANQADCgYIBgAAAA==.Ririko:BAAANQAECgUICgAAAA==.Ritzo:BAAANQAECgUICgAAAA==.',
Ro='Rocksanne:BAAANQADCggICQAAAA==.Rooguee:BAAANQAECgIIAwAAAA==.',
Ru='Rukkis:BAAANQAECgUIDAAAAA==.Rukâ:BAAANQADCgYJCAAAAA==.Rumi:BAABNQAECoEdAAIVAAkKYhovAwDAAgAVAAkKYhovAwDAAgAAAA==.Rumm:BAAANQADCgEIAQAAAA==.',
Ry='Ryeekan:BAAANQAECgUJCgAAAA==.Ryuma:BAAANQAECgYICgAAAA==.Ryumar:BAAANQAECgMIAwAAAA==.',
Sa='Sabrosura:BAAANQAECgUJCAAAAA==.Salsinor:BAAANQADCgUIBQAAAA==.Sathari:BAAANQAECgUICgAAAA==.',
Sc='Schaden:BAAANQAECgQIBwAAAA==.Scripter:BAAANQADCgUIBgAAAA==.',
Se='Seijo:BAAANQAECgEJAQAAAA==.Sekk:BAAANQAECgYIEQAAAA==.Selecta:BAAANQAECgEIAQAAAA==.Selexi:BAAANQADCggICAAAAA==.Selithira:BAAANQAECgQICAAAAA==.Sera:BAAANQADCgYICgAAAA==.',
Sh='Shabagnarang:BAAANQAECgQIDAAAAA==.Shalasyr:BAAANQAECgEIAgAAAA==.Shaletaz:BAAANQABCgQIBgAAAA==.Shamwowee:BAAANQADCgUIEgAAAA==.Shamzee:BAABNQAECoEdAAILAAgKiB0mHACtAgALAAgKiB0mHACtAgAAAA==.Sheyy:BAAANQAECgEIAQAAAA==.Shiftybonez:BAAANQADCgQIBQAAAA==.Shintok:BAAANQAECgQJBQAAAA==.Shuddarun:BAACNQAFFIEKAAIEAAUKgxlfAgDCAQAEAAUKgxlfAgDCAQA1AAQKgSQAAgQACQpRJB4FAJQDAAQACQpRJB4FAJQDAAAA.',
Si='Silverbakk:BAAANQABCgEIAQAAAA==.Simn:BAAANQAECgUJCgAAAA==.Sindraesong:BAAANQAECgUJCQAAAA==.',
Sk='Skithiryx:BAAANQAECgQIBAABNQAECgYJDAAIAAAAAA==.Skuldd:BAAANQABCgQICQAAAA==.',
Sl='Slayvylora:BAAANQADCgcJBwABNQAECggJHgAQACwcAA==.',
Sm='Smarte:BAAANQADCgEIAQABNQAECgcIDQAIAAAAAA==.Smolderpally:BAAANQADCgYIBgAAAA==.',
Sn='Sneakymoth:BAAANQADCgUIBQABNQAECgUJCgAIAAAAAA==.Snookums:BAAANQAECgEIAQAAAA==.',
So='Soarin:BAAANQADCgQIBAAAAA==.',
Sp='Spicymaker:BAAANQAECgYJCwAAAA==.',
St='Steelheart:BAAANQABCgQIBAAAAA==.Stop:BAAANQAECgMIAwAAAA==.Strifewood:BAAANQAECgUJBQAAAA==.Stumper:BAAANQAECgYJDAAAAA==.',
Su='Sux:BAAANQADCgMIAwAAAA==.',
Sy='Sybrina:BAAANQAECgUICwAAAA==.Sylvia:BAAANQAECgYJDwAAAA==.Syngeance:BAAANQAECgEIAQAAAA==.Synèsterwolf:BAAANQAECgcIBQAAAA==.',
['Sí']='Síf:BAAANQADCgUICAAAAA==.',
Ta='Tadeusz:BAAANQAECgUIBwAAAA==.Tamamò:BAAANQADCgYJCAAAAA==.Tanleros:BAAANQAECgUIBgAAAA==.Taquítos:BAAANQADCgIIAgAAAA==.',
Te='Telana:BAAANQADCgUIEgAAAA==.Tequitos:BAAANQAECgUJCgAAAA==.Tessla:BAAANQADCgYJDAAAAA==.',
Th='Theduk:BAAANQAECgQICAAAAA==.Theduke:BAAANQADCgIIAwAAAA==.Theliria:BAAANQADCgYIBgAAAA==.Thorias:BAABNQAECoEZAAIOAAgKLRwETwCeAgAOAAgKLRwETwCeAgAAAA==.Thtime:BAABNQAECoEYAAIOAAgK7hi8WwB6AgAOAAgK7hi8WwB6AgAAAA==.',
To='Tomoko:BAAANQADCgYICQAAAA==.Torment:BAAANQAECgYIEQAAAA==.',
Tr='Tristén:BAAANQAECgQICAAAAA==.Truvie:BAAANQADCgMIAwAAAA==.',
Tu='Tumbled:BAAANQAECgUJCgAAAA==.Tumbles:BAAANQADCgQIBQAAAA==.Tumni:BAAANQAECgEIAQAAAA==.',
['Tá']='Tángall:BAAANQABCgEIAQAAAA==.',
Ui='Ui:BAAANQADCgMIAwAAAA==.',
Ul='Ulnuk:BAAANQAECgYJEgAAAA==.Ulster:BAAANQADCgEIAQAAAA==.',
Un='Ungodly:BAAANQAECggICwAAAA==.Unholyshan:BAAANQADCgQIBAABNQADCgYJCwAIAAAAAA==.Unidus:BAAANQABCgUICAAAAA==.',
Uu='Uutr:BAAANQABCgEIAQAAAA==.',
Uv='Uvvolx:BAAANQADCgQJCAAAAA==.',
Va='Vadka:BAAANQADCgcIEQAAAA==.Vaeldrin:BAAANQAECgQIBQAAAA==.Vaha:BAAANQADCgcIDwAAAA==.Valkree:BAAANQAECgEIAQAAAA==.Valsavis:BAAANQAECgYIDwAAAA==.',
Ve='Veaolop:BAAANQABCggIEAAAAA==.Vellagosa:BAAANQADCggIHAAAAA==.Vernice:BAAANQADCgYJCwABNQAECgEIAQAIAAAAAA==.Verulan:BAAANQADCgUICAABNQADCgYIBgAIAAAAAA==.Vexidari:BAAANQADCgYIDAABNQAECggJHgAQACwcAA==.Vexomous:BAABNQAECoEeAAMQAAgKLByjAgCbAgAQAAgKLByjAgCbAgAFAAQK7gizOwDNAAAAAA==.',
Vi='Viiolet:BAAANQAECgYIBgAAAA==.',
Vo='Voidmayne:BAAANQAECgQIDQAAAA==.Vongogh:BAAANQADCgYICQAAAA==.Vonhelsing:BAAANQADCgEIAQAAAA==.',
Vy='Vynnara:BAAANQADCgEIAQAAAA==.Vyolent:BAAANQADCgYICwAAAA==.',
Wa='Warnox:BAAANQADCgcIBwAAAA==.',
We='Weiand:BAAANQAECgQICQAAAA==.Wevark:BAAANQAECgUJCgAAAA==.',
Wh='Whatami:BAAANQAECgYIDAAAAA==.Wholemilk:BAAANQADCggIIQAAAA==.Whîspers:BAAANQADCgYIEQAAAA==.',
Wi='Wilhellena:BAAANQAECgYIDwAAAA==.Wilhellfu:BAAANQADCgMIAwAAAA==.Winariel:BAAANQADCgYICwABNQAECgYJDQAIAAAAAA==.',
Wr='Writhesoul:BAAANQABCgIIAgABNQAECgYICQAIAAAAAA==.Wroughtsoul:BAAANQADCgIJAgAAAA==.Wrysoul:BAAANQAECgYICQAAAA==.',
Wy='Wynston:BAAANQADCgEIAQAAAA==.Wyrmheart:BAAANQADCgIIAwAAAA==.',
Xa='Xalatath:BAAANQADCgEIAQABNQAECgYICgAIAAAAAA==.Xaldred:BAAANQAECgUJCgABNQAECggJGgAJAN8QAA==.Xandir:BAAANQAECgYJDQAAAA==.Xarhunt:BAAANQADCgcIBAAAAA==.Xataryl:BAAANQADCgYIBgAAAA==.',
Xe='Xenzia:BAAANQADCgcICwAAAA==.Xeracil:BAAANQADCgQICgAAAA==.',
Xo='Xoric:BAABNQAECoEYAAIbAAgKphCtGADpAQAbAAgKphCtGADpAQAAAA==.',
Xy='Xyal:BAAANQAECgUICwAAAA==.Xyp:BAAANQADCgYIBgAAAA==.',
Ya='Yamaya:BAAANQADCgMJBQAAAA==.',
Yi='Yiago:BAAANQADCgYICgAAAA==.',
Yo='Youknow:BAAANQADCgcICwAAAA==.',
Za='Zaelia:BAAANQADCgEIAQAAAA==.Zary:BAAANQAECgIIAgAAAA==.Zaxhdk:BAEANQADCgMIAwABNQAECgYJDAAIAAAAAA==.Zaxhpal:BAEANQAECgYJDAAAAA==.',
Zi='Zid:BAAANQAECgIIAgAAAA==.Ziny:BAAANQADCgUIBQAAAA==.Ziparoo:BAAANQAECgQICAAAAA==.',
Zr='Zraven:BAAANQADCgEIAQAAAA==.',
['În']='Îniquitous:BAAANQAECgUJDgAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAANQAECgYIBgAAAA==.',
['Üb']='Übernasus:BAAANQADCgQIBgAAAA==.',
['ßy']='ßyrøßløøð:BAAANQABCgIIAgAAAA==.',
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
