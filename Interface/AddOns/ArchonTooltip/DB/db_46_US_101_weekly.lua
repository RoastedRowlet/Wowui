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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Monk-Windwalker','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Shaman-Elemental','Druid-Balance','Monk-Brewmaster','Paladin-Protection','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Frost','Shaman-Enhancement','Warrior-Fury','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJOgABAOkhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnXEQAbAQACAAQJ6RnXEQAbAQAuAAQKfxsAAgIACQldIA8GAK8CAAIACQldIA8GAK8CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgAECgEJAQABLgAECggJNAADABgPAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8qAAMEAAgJBw7tCgBrAQAEAAgJmA3tCgBrAQAFAAcJnwqPTAD7AAAAAA==.Altruist:BAABLgAECn8gAAMGAAgJ3RufDwAtAgAGAAgJ3RufDwAtAgAHAAIJnARuCgFAAAABLgAECgkJQQACAPcbAA==.',
Am='Amaethon:BAABLgAECn8WAAIIAAkJeArUJwAZAQAIAAkJeArUJwAZAQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn8/AAIJAAkJER/KDQDnAgAJAAkJER/KDQDnAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn86AAIBAAkJ6SEABQA9AwABAAkJ6SEABQA9AwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIKAAgJTAgWOwD6AAAKAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Around:BAAALgAECgUJBwAAAA==.Arrogant:BAAALgADCgMJAwAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn85AAQEAAkJsBvWAgCEAgAEAAkJsBvWAgCEAgAMAAQJpxQOIAD0AAAFAAEJsQPenQAiAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
Au='Aunyx:BAABLgAECn9BAAINAAkJlxbkBAA7AgANAAkJlxbkBAA7AgAAAA==.',
Az='Azbogah:BAABLgAECn8VAAMOAAYJjQJkAgCqAAAOAAYJjQJkAgCqAAAPAAEJaQHk0gEUAAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAQAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAARAGccAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8tAAIKAAkJyRpyDgC4AgAKAAkJyRpyDgC4AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAALAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB/KdQBUAQADAAYJRB/KdQBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJDAAAAA==.Birdymage:BAABLgAECn8ZAAISAAUJHBQ3yQD8AAASAAUJHBQ3yQD8AAAAAA==.',
Bl='Blightbeard:BAABLgAECn8YAAITAAgJ6gn1jQBJAQATAAgJ6gn1jQBJAQAAAA==.Blîss:BAAALgAFFAEJAgAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAcJIAATAHkUAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.',
Br='Brut:BAABLgAECn8hAAIHAAkJNx5iSACtAQAHAAkJNx5iSACtAQAAAA==.',
Bu='Bustus:BAABLgAECn80AAIUAAkJAg1hQgCHAQAUAAkJAg1hQgCHAQAAAA==.',
Ca='Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8fAAQVAAgJWhUxHgDUAQAVAAgJWhUxHgDUAQABAAYJ+RbYJQChAQAWAAMJexRmSADEAAAAAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8hAAIPAAcJ7g+fvAANAQAPAAcJ7g+fvAANAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8iAAISAAYJaxP2ogA2AQASAAYJaxP2ogA2AQAAAA==.Cherub:BAAALgADCgMJAwAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAOAAEJrwGvogAYAAAAAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn9BAAICAAkJ9xu/BwCFAgACAAkJ9xu/BwCFAgAAAA==.Corannis:BAABLgAECn81AAIXAAkJMRmuFABFAgAXAAkJMRmuFABFAgAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJDgAYAKIJAA==.',
Cr='Cranberries:BAABLgAECn8bAAMWAAcJyxdVJwCLAQAWAAYJpxhVJwCLAQABAAcJNRC4LwBgAQAAAA==.Crockett:BAAALgADCggJCAABLgAECgYJDwALAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgIJAgAAAA==.Curtis:BAAALgAECgYJDQABLgAECgkJMgAZAEEfAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAECgkJPAAGANEVAA==.Damaso:BAAALgAECgcJCwAAAA==.Dantez:BAACLgAFFH8FAAMYAAUJpw1xJwD1AAAYAAQJpw1xJwD1AAAUAAEJDA0gbABBAAAuAAQKfyEABBgACQk8IggEACIDABgACQk8IggEACIDABQABgncDvZeABkBAAgAAgk/E9oCAHYAAAAA.Darkgenie:BAAALgAECgcJDQAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8wAAIHAAkJEBtOHgBfAgAHAAkJEBtOHgBfAgAAAA==.Dawnmane:BAAALgAFFAEJAQAAAA==.',
De='Delderach:BAABLgAECn8jAAIaAAgJ4BWdFACGAQAaAAgJ4BWdFACGAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn87AAITAAkJ+BwTGwCkAgATAAkJ+BwTGwCkAgAAAA==.',
Di='Dirkette:BAABLgAECn8rAAIBAAkJdAQRNgA8AQABAAkJdAQRNgA8AQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJKwABAHQEAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJKwABAHQEAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAAALgADCgEJAQABLgAECgkJPAAGANEVAA==.Dokai:BAABLgAECn84AAIRAAkJZxx2CwCLAgARAAkJZxx2CwCLAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECggJFQAKAE8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJOgAbAHcWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBgAAAA==.Drewella:BAAALgADCgkJCQAAAA==.',
El='Elaenei:BAAALgADCgkJLAAAAA==.Eliance:BAABLgAECn8jAAINAAgJoARvFADiAAANAAgJoARvFADiAAAAAA==.Elienn:BAAALgAECgMJBAAAAA==.Elisham:BAAALgADCgkJCQAAAA==.Elsewhere:BAABLgAECn8hAAMFAAkJkw/IJwClAQAFAAkJkw/IJwClAQAMAAIJawYwQQAkAAAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Eo='Eog:BAAALgAECgkJCQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8qAAIbAAkJmhZMFQDCAQAbAAkJmhZMFQDCAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgUJBQAAAA==.',
Fa='Fabulush:BAAALgAECgMJAwAAAA==.Fatherbetter:BAAALgAECgYJCAABLgAFFAIJBQAHAHQWAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAATAHQGAA==.Feloras:BAAALgAECgYJEwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.',
Fo='Foxina:BAAALgAECgQJCAAAAA==.',
Fu='Fusaa:BAABLgAECn9IAAIcAAkJKxmjIABhAgAcAAkJKxmjIABhAgAAAA==.',
Ga='Gahzoo:BAAALgADCgQJAQAAAA==.Gallindo:BAAALgAECgEJAQABLgAECgcJFgAdAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garu:BAAALgADCgQJBAABLgAECgkJLwATAMMVAA==.',
Ge='Gelst:BAAALgAECgUJBwAAAA==.Gerbzarrion:BAABLgAECn8hAAISAAgJhgiysgAdAQASAAgJhgiysgAdAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAABLgAECn88AAIGAAkJ0RWrEgAEAgAGAAkJ0RWrEgAEAgAAAA==.Giragon:BAAALgADCgQJBAAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8JAAITAAQJjgzGhAD/AAATAAQJjgzGhAD/AAAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Hawknnin:BAABLgAECn8gAAIOAAgJkSDVDwCcAgAOAAgJkSDVDwCcAgAAAA==.Hawknnip:BAAALgADCgkJCQABLgAECggJIAAOAJEgAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8KAAIDAAMJ3xImXwDmAAADAAMJ3xImXwDmAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgMJAwAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAWAMsXAA==.',
In='Inari:BAAALgADCgkJCQABLgAECgYJCgALAAAAAA==.',
Ip='Ipwnallnoobs:BAACLgAFFH8FAAITAAIJgwhH4QCEAAATAAIJgwhH4QCEAAAuAAQKfx0AAhMACQnVDbxaALYBABMACQnVDbxaALYBAAAA.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAdAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn8xAAMUAAgJCh0LGACGAgAUAAgJCh0LGACGAgAYAAEJWAOQpgAaAAAAAA==.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8XAAIPAAcJrhy5UADWAQAPAAcJrhy5UADWAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIeAAkJ0hdHBwAQAgAeAAkJ0hdHBwAQAgAAAA==.Kaimare:BAAALgADCgUJCgAAAA==.Kandistars:BAABLgAECn8oAAIYAAkJoBF1IQC9AQAYAAkJoBF1IQC9AQAAAA==.Kasia:BAABLgAECn8lAAIJAAgJnhtUJwAjAgAJAAgJnhtUJwAjAgAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAITAAgJiBbUYACnAQATAAgJiBbUYACnAQAAAA==.Kirarah:BAABLgAECn87AAIDAAkJtiTCCwD1AgADAAkJtiTCCwD1AgAAAA==.Kirarose:BAACLgAFFH8VAAMVAAYJexmJDACZAQAVAAYJexmJDACZAQAWAAIJ2gG2NABDAAAuAAQKfxwAAxUACQmmImcRAEsCABUACQmmImcRAEsCABYAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn84AAIKAAkJng/8LgDAAQAKAAkJng/8LgDAAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8WAAIFAAgJRwqlPgAvAQAFAAgJRwqlPgAvAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgALAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIQAAgJRhvIBQApAgAQAAgJRhvIBQApAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8tAAIDAAkJOyFiEADNAgADAAkJOyFiEADNAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8OAAIYAAMJoglFNgClAAAYAAMJoglFNgClAAAuAAQKfz0AAwgACQn1GJoKADsCAAgACQn1GJoKADsCABgACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8PAAMdAAQJkwRGIQDPAAAdAAQJlwFGIQDPAAADAAIJhwfljwCAAAAuAAQKfyUAAwMACQmKCXx9AEQBAAMACAkjCnx9AEQBAB0AAgnOBnpQAG0AAAAA.',
Lj='Ljósálfr:BAABLgAECn9KAAICAAkJLyQYAADXAgACAAkJLyQYAADXAgAAAA==.',
Lo='Lochramae:BAABLgAECn86AAIbAAkJdxbuFwClAQAbAAkJdxbuFwClAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAACLgAFFH8FAAIHAAIJdBYKewCIAAAHAAIJdBYKewCIAAAuAAQKfyUAAgcACAlzIbEWAI8CAAcACAlzIbEWAI8CAAAA.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCgkJFwABLgAECggJFQAKAE8VAA==.Magjistar:BAAALgADCgkJDAAAAA==.Mahangi:BAAALgADCgkJHAAAAA==.Mamimisan:BAABLgAECn8xAAIJAAkJvB+yCQAZAwAJAAkJvB+yCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJEQAAAA==.',
Mi='Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMIAAcJoRh2FgCfAQAIAAcJoRh2FgCfAQAUAAMJ7AaHsQBWAAABLgAECgkJKQAIAPsaAA==.Mizeroni:BAAALgAECgEJAQABLgAECgkJKQAIAPsaAA==.Mizkat:BAABLgAECn8pAAQIAAkJ+xrwCABcAgAIAAkJ+xrwCABcAgAfAAEJSw6tUQA1AAAUAAIJHA2bzwAvAAAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn80AAMDAAgJGA9ZaAByAQADAAgJGA9ZaAByAQAgAAEJ1QF6RgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQdAAgJlSVXBgCfAgAdAAcJ4iRXBgCfAgADAAYJliTUQADgAQAgAAIJ/SN5HwCzAAAAAA==.',
['Më']='Mërcy:BAAALgAECgQJBQAAAA==.',
Na='Naklus:BAAALgAECgcJDwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8tAAIJAAkJJxb4AAC2AQAJAAkJJxb4AAC2AQABLgAECgkJPAAGANEVAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgYJCwAAAA==.',
Nl='Nlani:BAAALgAECggJDgAAAA==.',
No='Noblesfan:BAAALgADCgQJBgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAAALgAFFAQJBAABLgAFFAgJGgAHACshAA==.',
Or='Orees:BAAALgAECgEJAQAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIfAAYJMCAKDgDVAQAfAAYJMCAKDgDVAQAAAA==.',
Pa='Parne:BAAALgADCggJDQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgMJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn82AAIOAAkJ3xndEQCFAgAOAAkJ3xndEQCFAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ps='Psychoticc:BAAALgAECgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn9BAAIhAAkJLRNVBwDhAQAhAAkJLRNVBwDhAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJNAADABgPAA==.Ranron:BAAALgAECgUJCQAAAA==.Rassaphore:BAABLgAECn8hAAIRAAgJfiEJCgCjAgARAAgJfiEJCgCjAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8kAAIiAAgJwxXxDACoAQAiAAgJwxXxDACoAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAHADceAA==.Rionach:BAABLgAECn8/AAIIAAkJLwn6KQAMAQAIAAkJLwn6KQAMAQAAAA==.Ritsara:BAABLgAECn8UAAIaAAcJyQ0hJgDlAAAaAAcJyQ0hJgDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgALAAAAAA==.Rivon:BAABLgAECn8jAAMOAAkJgxjGIAD9AQAOAAgJWBfGIAD9AQAPAAEJagvvfQE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAHAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMWAAkJYh8JDACmAgAWAAgJPiAJDACmAgAVAAEJAhlJeQBNAAAAAA==.',
Se='Seanan:BAABLgAECn8hAAIjAAkJlyA0AgABAwAjAAkJlyA0AgABAwABLgAECgkJKQAPAHgdAA==.Seanx:BAABLgAECn8pAAMPAAkJeB2ZIgB7AgAPAAkJeB2ZIgB7AgAaAAYJhhIZJAD0AAAAAA==.',
Sh='Shenlong:BAABLgAFFH8IAAITAAIJrhlg3gCFAAATAAIJrhlg3gCFAAAAAA==.Shigurexx:BAABLgAECn9MAAMDAAkJaCGWAABwAgADAAkJaCGWAABwAgAgAAcJdhotDAChAQAAAA==.Shoe:BAABLgAECn9HAAMEAAkJBhyEAwBeAgAEAAkJBhyEAwBeAgAFAAcJoBHQJQCxAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIPAAcJ8gOo9wDBAAAPAAcJ8gOo9wDBAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgQJBQAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgcJBAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Steelbutt:BAAALgAECgEJAQAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBgAAAA==.',
Ta='Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8lAAICAAgJlxY2FQCgAQACAAgJlxY2FQCgAQAAAA==.Tarkahunt:BAAALgADCgQJBAAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIIAAQJiBDBFQDUAAAIAAQJiBDBFQDUAAAuAAQKfxwAAggACQmwH6EFAK8CAAgACQmwH6EFAK8CAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAISAAYJNSAdWADVAQASAAYJNSAdWADVAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.',
To='Toom:BAABLgAECn8jAAIDAAgJGg9acgBbAQADAAgJGg9acgBbAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgIJAgABLgAECgkJPAAGANEVAA==.Trophyhubby:BAABLgAECn8qAAMVAAkJIAdyNQBBAQAVAAkJIAdyNQBBAQAWAAcJ5Qw2OwAJAQAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAECgkJSgACAC8kAA==.Tuladrin:BAAALgADCgQJBAAAAA==.Tumbler:BAAALgADCgkJCQABLgAECgkJMgAZAEEfAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8gAAMTAAcJeRTzJgDPAQATAAYJeRTzJgDPAQAbAAEJAAC9WQAAAAAuAAQKfx8AAxMACQnZHtkiALQCABMACAn/HtkiALQCABsAAwkMGlszAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAcJIAATAHkUAA==.',
Us='Usato:BAABLgAECn8VAAIKAAgJTxWULwC9AQAKAAgJTxWULwC9AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8dAAIPAAgJuQjBxgD/AAAPAAgJuQjBxgD/AAAAAA==.Valvet:BAAALgADCgkJNAAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAITAAUJdAaEiQD3AAATAAUJdAaEiQD3AAAuAAQKfxcAAxMACQlHE86BAGABABMACAmdCc6BAGABABsABQm7Gx0kADIBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJDQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIHAAcJHiTjJQBvAgAHAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwALAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgALAAAAAA==.',
Vy='Vylus:BAAALgAECgYJEwAAAA==.',
['Vá']='Vásh:BAAALgADCgkJEQAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgIJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgQJCQAAAA==.William:BAABLgAECn8sAAIDAAkJXSK5BwAfAwADAAkJXSK5BwAfAwAAAA==.Windee:BAABLgAECn8aAAIRAAYJ7g5ARQDqAAARAAYJ7g5ARQDqAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMgAAgJdwvkGwDPAAADAAYJzg7skQAcAQAgAAcJkwbkGwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMQAAQJuw4wDgCjAAAcAAMJgAgChAC+AAAQAAIJuhUwDgCjAAAuAAQKfyYABBAACQk0HasEAE8CABAACQk0HasEAE8CABwABgmmEu1wAFgBACEAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAABLgAECn9FAAIkAAkJNSGmBQAFAwAkAAkJNSGmBQAFAwAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8QAAIjAAQJWg2vCwAGAQAjAAQJWg2vCwAGAQAuAAQKfxwAAiMACQnrHRYFAJcCACMACQnrHRYFAJcCAAAA.Zalixte:BAAALgADCgUJBQAAAA==.Zatika:BAABLgAECn85AAMSAAkJuhl1OAA3AgASAAkJxRZ1OAA3AgAlAAcJ1xg6BQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8jAAIYAAgJPQmmRQD2AAAYAAgJPQmmRQD2AAAAAA==.',
Zm='Zmija:BAAALgAECgMJBAAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
