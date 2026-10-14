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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Warrior-Arms','Warrior-Fury','Priest-Discipline','Paladin-Protection','Druid-Balance','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Priest-Holy','Priest-Shadow','Paladin-Retribution','Monk-Mistweaver','Mage-Arcane','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','Mage-Frost','Rogue-Outlaw','Druid-Guardian','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Druid-Feral','Warrior-Protection','Shaman-Enhancement','DemonHunter-Havoc','Warlock-Affliction',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=53,date='2026-10-13',data={Ag='Agp:BAACNQAFFH8HAAIBAAUKTBWTCwCSAQABAAUKTBWTCwCSAQA1AAQKfx8AAwEACQqPI6UbACgDAAEACQqPI6UbACgDAAIAAQoAAAiMADEAAAAA.',
Ah='Aharan:BAAANQAECgUIDwAAAA==.',
Al='Aleria:BAAANQADCgQIBQAAAA==.',
An='Andraxy:BAAANQAECgYICAABNQAFFAQIDwADAHAaAA==.Anielor:BAAANQABCgQIBAAAAA==.',
Ar='Aratar:BAACNQAFFH8HAAMEAAQKYxieIAD0AAAEAAMKYxieIAD0AAAFAAEKAADWBQBJAAA1AAQKfyAAAgQACAoLHchkAF0CAAQACAoLHchkAF0CAAAA.Arcadia:BAAANQAECgUICAAAAA==.Arcticheat:BAAANQAECgQIBAABNQAECgkJJgAGAF4cAA==.Arizona:BAAANQAECgYIEwAAAA==.Arkantos:BAAANQAECgcIEwAAAA==.',
As='Asta:BAAANQADCgYIBgAAAA==.',
At='Athius:BAAANQADCgUIBQAAAA==.',
Au='Automobeer:BAAANQADCgMIAwAAAA==.',
Aw='Awake:BAAANQAECgcIBQAAAA==.',
Ba='Bakedsham:BAAANQADCgEIAQAAAA==.Bayareadady:BAAANQADCgYIDgAAAA==.',
Be='Belandra:BAAANQADCgYIAwABNQAECgcIGgAHADYhAA==.',
Bi='Biggbird:BAABNQAECn8XAAIIAAYKUg78YQBCAQAIAAYKUg78YQBCAQAAAA==.',
Bj='Bjord:BAABNQAECn8oAAMBAAkK/x91GwApAwABAAkK/x91GwApAwACAAEK3gAkngAaAAABNQADCggICAAJAAAAAA==.',
Bl='Blackplague:BAAANQABCgEIAQAAAA==.',
Bo='Boong:BAAANQADCgQIBAAAAA==.Bossdeath:BAAANQAECgcICAABNQAECggILgAKAPglAA==.Bossdierr:BAAANQAECggIEwABNQAECggILgAKAPglAA==.Bossdisan:BAAANQAECggIEwABNQAECggILgAKAPglAA==.Bossdiyi:BAABNQAECn8oAAIEAAkK1CQgEgBzAwAEAAkK1CQgEgBzAwABNQAECggILgAKAPglAA==.Bosswudi:BAABNQAECn8uAAMKAAgK+CVFMAAcAgAKAAUKxCVFMAAcAgALAAUKUiV2GAAWAgAAAA==.',
Br='Bruh:BAAANQAECgUIBgAAAA==.',
Bu='Buffmw:BAEANQADCgIIAgABNQAFFAkJGAAMABseAA==.Buttshaman:BAAANQAECgcIDQAAAA==.',
Ca='Cazadòr:BAAANQADCggICAAAAA==.',
Ch='Choco:BAAANQAECggIDQAAAA==.Chromiepip:BAAANQADCgEIAQAAAA==.',
Co='Colt:BAABNQAECn8gAAIHAAgKqh9CFABgAgAHAAgKqh9CFABgAgAAAA==.Corrosiveman:BAABNQAECn8XAAMNAAcKhxVccADIAQANAAcKhxVccADIAQAOAAEKAAALeQAzAAAAAA==.Cowned:BAAANQADCgYIBgABNQAFFAIIBgAPAAgTAA==.',
Cr='Creamy:BAAANQAECgUJCwAAAA==.',
Da='Daer:BAAANQADCgQIBAAAAA==.Danielpana:BAACNQAFFH8PAAIDAAQKcBqsCQAtAQADAAQKcBqsCQAtAQA1AAQKfyYAAgMACQoNIyUMABIDAAMACQoNIyUMABIDAAAA.Darkfyre:BAABNQAECn8hAAIQAAgKlRJLGgDXAQAQAAgKlRJLGgDXAQAAAA==.Darkraider:BAAANQAFFAEIAgAAAA==.',
Di='Dinkledots:BAAANQADCgUIBQABNQAECggIGQARADMRAA==.Dinks:BAABNQAECn8ZAAIRAAgKMxEmxQD4AQARAAgKMxEmxQD4AQAAAA==.Dishwasher:BAAANQAECggIEQAAAA==.',
Do='Docc:BAAANQAECgYICgAAAA==.Doe:BAAANQADCgYIBgABNQAECgcIHgASACcaAA==.Doii:BAAANQADCgQIBAABNQAECgcIHgASACcaAA==.',
Dr='Dragonfyre:BAAANQAECgEIAQAAAA==.Drood:BAAANQADCgUIBQAAAA==.',
Du='Duration:BAAANQAECgYIDwAAAA==.',
Ek='Ektyr:BAAANQAECgUICgABNQADCggICAAJAAAAAA==.',
Em='Emiliam:BAAANQAECggIEQAAAA==.',
Er='Erdrick:BAAANQAECgQIBgAAAA==.Ero:BAAANQAECgcICgAAAA==.',
Ev='Evërjzy:BAAANQADCggIDAAAAA==.',
Fa='Faded:BAAANQAECgMIAwAAAA==.Fatheralvin:BAAANQABCgUIDAAAAA==.',
Fe='Feronar:BAABNQAECn8eAAMFAAcKzAxyEgB4AQAFAAcKzAxyEgB4AQAEAAIK1AQaQQFHAAAAAA==.',
Fl='Flowermom:BAAANQADCgQIBAAAAA==.Flume:BAAANQAECgcIDAAAAA==.',
Fx='Fx:BAABNQAECn8eAAISAAcKJxp4XwDtAQASAAcKJxp4XwDtAQAAAA==.',
['Fú']='Fúsión:BAEANQAECgEIAQABNQAECgkJGAAKAGAhAA==.',
Ga='Galedra:BAABNQAECn8aAAIHAAcKNiE6EwBsAgAHAAcKNiE6EwBsAgAAAA==.Gargomash:BAAANQAECgIIAgAAAA==.',
Gi='Gin:BAAANQADCggIGgABNQAFFAMIBQABAKkaAA==.',
Gj='Gjana:BAABNQAECn8vAAMTAAkKJBq4MwC4AgATAAkKJBq4MwC4AgAUAAUK2gVyPQDLAAAAAA==.',
Go='Goma:BAAANQAECgQIBAAAAA==.Goomy:BAAANQAECgQIBwAAAA==.Gorlash:BAAANQADCgYIBgAAAA==.',
Gr='Gravemaw:BAAANQADCgcJBwAAAA==.Greenboi:BAAANQADCgcIEgAAAA==.Grimfeather:BAAANQAECgYICQAAAA==.Grimgeth:BAABNQAECn83AAQVAAkKixpYMgBfAgAVAAkKixpYMgBfAgAWAAYKVhlGTwC1AQAXAAcKahIXRQCmAQAAAA==.Grimwrath:BAAANQAECgcIEgABNQAECgkJNwAVAIsaAA==.Grouch:BAABNQAECn8vAAIYAAkKvRu8KwDNAgAYAAkKvRu8KwDNAgABNQAECgkJLwATACQaAA==.',
Gu='Guanine:BAABNQAECn8YAAMXAAgKsxS+PgDJAQAXAAcKPRa+PgDJAQAVAAYKRAlCgwAOAQAAAA==.Gudeath:BAAANQAECgYIDwAAAA==.Guishin:BAAANQAECgEIAQAAAA==.Guyver:BAAANQADCgYIBgAAAA==.',
He='Heidriel:BAAANQADCgQIBgAAAA==.Heontwo:BAAANQAECgIIAgAAAA==.Heshan:BAABNQAECn83AAMZAAkK7RsrBQDEAgAZAAkK7RsrBQDEAgARAAcKsxFXxQD4AQAAAA==.',
Ho='Hoodwink:BAAANQADCgYIBwAAAA==.',
Im='Imortathorin:BAAANQADCggJCQAAAA==.',
In='Insanities:BAABNQAECn8mAAMGAAkKXhx4AwCzAgAGAAgK5xx4AwCzAgANAAgKFRNZXgACAgAAAA==.',
Ja='Jaidie:BAAANQAECgQICwAAAA==.Jarco:BAECNQAFFH8MAAMaAAYKHBqgAAD8AQAaAAYKHBqgAAD8AQAKAAEKAAA0HQBOAAA1AAQKfyUAAxoACQoJJHMBAHEDABoACQraInMBAHEDAAsACQqkHcMKAMYCAAAA.',
Je='Jebussaves:BAAANQADCggICQAAAA==.Jerlonge:BAAANQAECgEIAQAAAA==.',
Jo='Joak:BAAANQADCgIIAgAAAA==.',
Ka='Kaidou:BAABNQAFFH8HAAITAAUK3hmzDgCUAQATAAUK3hmzDgCUAQAAAA==.Kasaar:BAAANQADCgIIAgAAAA==.',
Ki='Kitsune:BAABNQAECn8mAAMbAAgKvwjhMwD9AAAIAAgKbgaWWgBkAQAbAAYKrAnhMwD9AAAAAA==.',
Kr='Kryptix:BAABNQAECn8ZAAINAAgKeB5jLQCwAgANAAgKeB5jLQCwAgAAAA==.',
Ku='Kubicki:BAAANQAECgcIDwAAAA==.Kubimage:BAAANQADCgYIBgAAAA==.Kurta:BAAANQADCgEIAQAAAA==.',
La='Lastlife:BAAANQADCgUIDgAAAA==.Lastshamurai:BAAANQADCgUIBQAAAA==.Layona:BAAANQAECgYIDQAAAA==.',
Li='Linelli:BAACNQAFFH8PAAQcAAUK4yVaAAATAgAcAAUK4yVaAAATAgABAAEKAAC9LQBkAAACAAEKGACRKAALAAA1AAQKfyIAAxwACAr3Jf0AAIIDABwACAr3Jf0AAIIDAAEABwrlG6F5ABgCAAAA.',
Lo='Lobixona:BAAANQAECgEIAQAAAA==.Lowakacho:BAAANQADCgQIBAAAAA==.',
Lx='Lxrbread:BAABNQAECn8nAAQdAAkKtAaJJACbAQAdAAkKtAaJJACbAQAeAAYKoxKKDgBaAQAfAAMKAQULMgB9AAAAAA==.',
['Lì']='Lìlith:BAAANQAECgQIBAABNQAFFAYICwAgAEobAA==.',
Ma='Maccazilla:BAAANQADCgYICgAAAA==.Magdalena:BAABNQAECn8hAAIDAAkKMCMzBACPAwADAAkKMCMzBACPAwABNQAFFAIIAgAJAAAAAA==.Martini:BAAANQAECgQIBwAAAA==.',
Me='Meatkleaver:BAAANQAECgcIEwAAAA==.Mech:BAABNQAECn9qAAMbAAkK1iYkAAAVBAAbAAkK1iYkAAAVBAAhAAgK4h+qBwDfAgAAAA==.Mediumroast:BAAANQADCgcIBwAAAA==.Merbs:BAAANQAECgQIBwAAAA==.',
Mo='Mochi:BAABNQAECn8aAAISAAgKeRgFTAAwAgASAAgKeRgFTAAwAgAAAA==.Mommydeath:BAAANQADCgYIBgAAAA==.Morbius:BAAANQAECggICAAAAA==.Morholt:BAAANQADCgMIAwAAAA==.Morix:BAAANQABCgcICgAAAA==.',
Ne='Necromortas:BAABNQAECn8aAAMTAAcKCBaVfwDjAQATAAcKCBaVfwDjAQAUAAEKEgMqgQAqAAAAAA==.',
Ni='Nipnaxes:BAAANQADCgIIAgAAAA==.Nira:BAAANQADCgYICgAAAA==.',
No='Notlrahc:BAAANQAECgQIDAAAAA==.',
Ny='Nyki:BAAANQADCgYICAAAAA==.',
Os='Oscrixi:BAAANQABCgcICAAAAA==.',
Pa='Padriac:BAAANQADCggICwAAAA==.Paolinelli:BAAANQAECgcICQABNQAFFAUIDwAcAOMlAA==.Pattêrn:BAAANQADCggIDQAAAA==.Paìn:BAACNQAFFH8LAAIgAAYKShuCAwAcAgAgAAYKShuCAwAcAgA1AAQKf00AAiAACQq2JkcAAAcEACAACQq2JkcAAAcEAAAA.',
Pe='Pedri:BAACNQAFFH8NAAMVAAMK3ibTCgBfAQAVAAMK3ibTCgBfAQAXAAMKhyShCgAzAQA1AAQKfzIAAxUACQr4JmIHAIkDABUACQr4JmIHAIkDABcAAgpwGP+KAH8AAAAA.Pedrok:BAABNQAECn8rAAMEAAgKJAvVqgCtAQAEAAgKJAvVqgCtAQAiAAEKAADzSwAZAAAAAA==.',
Ph='Phael:BAAANQAECgMIBAAAAA==.',
Pi='Pinkdot:BAAANQADCgYIBwAAAA==.',
Po='Popius:BAAANQAECgQICQAAAA==.Pothtwo:BAAANQADCgUIBQAAAA==.',
Pr='Prentiss:BAAANQADCgcIDAABNQADCggICAAJAAAAAA==.Promorph:BAAANQAECgEIAgAAAA==.',
Pu='Puups:BAAANQADCgYICAAAAA==.',
['Pì']='Pìngü:BAAANQAECgcIEwAAAA==.',
Ra='Raph:BAABNQAECn8rAAIVAAkKgiDOEwAYAwAVAAkKgiDOEwAYAwAAAA==.',
Re='Rednoser:BAAANQAECggIEAAAAA==.Redthepriest:BAAANQAECgEIAQAAAA==.Remmahcm:BAAANQAECggIDgAAAA==.Reverse:BAAANQADCgYIBgABNQAFFAUIBwABAEwVAA==.Rexnor:BAAANQADCgQIBAABNQAECgQIBgAJAAAAAA==.',
Sa='Sagas:BAABNQAECn8nAAIjAAkKUh1XBgAfAwAjAAkKUh1XBgAfAwAAAA==.Sambiquira:BAAANQAECgIIAgAAAA==.Sarial:BAABNQAECn8qAAMkAAkKlST4AwCxAwAkAAkKlST4AwCxAwAgAAkKbhpcGwB5AgAAAA==.Saryeras:BAAANQADCgQIBAABNQADCggICAAJAAAAAA==.',
Sc='Scrit:BAAANQAECgQICQAAAA==.',
Si='Sil:BAAANQAECgcIEAAAAA==.',
Sk='Ska:BAAANQAECgIIBAAAAA==.',
So='Softbutt:BAAANQADCgIIAgAAAA==.Soulreaper:BAAANQADCgcJDgABNQAECgcIHgASACcaAA==.',
Sq='Squish:BAAANQADCgEJAQAAAA==.',
St='Staby:BAAANQADCgYIBgABNQAECgMIAwAJAAAAAA==.',
Sy='Syrensong:BAAANQABCgUIBgAAAA==.',
Ta='Tapechewer:BAAANQADCgUICgAAAA==.Tatax:BAAANQAECggIDAABNQAFFAQIDwADAHAaAA==.',
Te='Tertlepaws:BAAANQAECgcIBwAAAA==.Teto:BAAANQADCgYIBwAAAA==.Tetsunen:BAAANQAECgQIDgAAAA==.',
Th='Thralson:BAAANQADCgQIBAAAAA==.',
To='Tog:BAAANQADCgIIAgAAAA==.Toggywoggy:BAABNQAECn8aAAIlAAgKkBZDBwApAgAlAAgKkBZDBwApAgAAAA==.Tortoisetoes:BAAANQAECgYIDwABNQAECgcIBwAJAAAAAA==.',
Tr='Trillex:BAAANQABCgUIBAAAAA==.',
Tu='Turok:BAAANQAECgUIBwAAAA==.',
Ur='Urra:BAAANQAECggIBAAAAA==.',
Ve='Velo:BAAANQAECgEIAQAAAA==.Verminardy:BAAANQABCgMIBAAAAA==.',
Wa='Wanheda:BAABNQAECn8fAAIBAAkKaxzcIwAGAwABAAkKaxzcIwAGAwAAAA==.Wargyu:BAACNQAFFH8NAAIEAAQKlBhMGABUAQAEAAQKlBhMGABUAQA1AAQKf0gAAgQACQoXJGIPAIEDAAQACQoXJGIPAIEDAAAA.Watertort:BAABNQAECn8fAAMSAAgKExmuPgBjAgASAAgKExmuPgBjAgAYAAMKTArh+ACaAAAAAA==.',
We='Weezard:BAAANQADCgYIEQABNQAECgkJLwATACQaAA==.',
Wo='Woobley:BAAANQADCgcICQAAAA==.',
Wy='Wyarlok:BAAANQAECgMIAwAAAA==.',
Xa='Xandraz:BAAANQADCgEIAQAAAA==.',
Yn='Ynup:BAAANQADCgcIFQAAAA==.',
Za='Zardnax:BAAANQAECgEIAQAAAA==.',
Ze='Zel:BAAANQADCgIIAgAAAA==.Zenin:BAAANQAECgUICAABNQADCggICAAJAAAAAA==.Zenjamin:BAAANQAECgEIAQABNQADCggICAAJAAAAAA==.Zenu:BAAANQADCggICAAAAA==.',
Zu='Zuleika:BAAANQAECgcIEQAAAA==.',
['Øm']='Ømen:BAAANQAECgMIBAAAAA==.',
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
