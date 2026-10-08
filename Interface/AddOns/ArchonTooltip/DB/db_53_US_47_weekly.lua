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

local lookup = {'Warlock-Affliction','Priest-Holy','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Unknown-Unknown','Warlock-Demonology','Mage-Frost','Mage-Arcane','Warrior-Protection','Warrior-Arms','DeathKnight-Blood','Monk-Mistweaver','DeathKnight-Unholy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Warrior-Fury','Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Frost','Monk-Brewmaster','Paladin-Holy','Druid-Balance','Monk-Windwalker','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Druid-Restoration','Evoker-Preservation','Priest-Discipline','Rogue-Outlaw','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aalfie:BAAANQAECgQIBwABNQAECggIJgABAHgQAA==.',
Ad='Adaric:BAAANQADCgUIBQAAAA==.Aderren:BAABNQAECoEmAAMCAAgKLRy7NQBvAgACAAgKLRy7NQBvAgADAAEKdREmagA5AAAAAA==.',
Ae='Aeir:BAAANQAECgQJCAAAAA==.Aeladra:BAAANQADCggICAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAACNQAFFIEWAAMEAAYKCxzHAQBJAgAEAAYKrxvHAQBJAgAFAAUKfBbaBQCuAQA1AAQKgTEAAwQACQq8JSUBANQDAAQACQp4JSUBANQDAAUACApDJCgGABgDAAAA.',
Ag='Agarn:BAABNQAECoEdAAIGAAkKkh2hHAAFAwAGAAkKkh2hHAAFAwABNQAECggIDwAHAAAAAA==.Aghanaar:BAAANQAECgYIEgAAAA==.Agidan:BAABNQAECoEcAAIIAAkK6wspcgDhAQAIAAkK6wspcgDhAQAAAA==.Aglarel:BAAANQADCgEIAQAAAA==.Aguthus:BAAANQADCgYICgAAAA==.',
Ai='Airryon:BAAANQADCgMIAwAAAA==.Aitch:BAAANQADCgcJBwAAAA==.',
Ak='Akaibara:BAAANQADCggIHwAAAA==.',
Al='Alcazor:BAAANQADCgUIBQAAAA==.Alizar:BAAANQAECgcIEgAAAA==.Alleriá:BAABNQAECoElAAMJAAgK5iLdDwB/AQAKAAcK+R8mhQBbAgAJAAQKwSLdDwB/AQAAAA==.Almaholzhert:BAAANQAECgEJAQAAAA==.Alor:BAABNQAECoEaAAMLAAcKpgfGIQAPAQALAAcKvQbGIQAPAQAMAAUKHgXq7QDTAAAAAA==.Alundareth:BAABNQAECoEbAAIKAAkKjRuLPgD7AgAKAAkKjRuLPgD7AgAAAA==.Alynnis:BAAANQADCgUIBQAAAA==.Alysanne:BAAANQAECgQIBAAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAAHAAAAAA==.',
An='Anaphora:BAAANQABCgQIBAAAAA==.Angelmoon:BAAANQADCggIEAAAAA==.Angryart:BAAANQAECgIIAgABNQAECggIHQANAPofAA==.Anguissette:BAAANQAECgYIEAAAAA==.Anklehumper:BAAANQAECgMIAwABNQAECgQIDAAHAAAAAA==.Anniellusion:BAABNQAECoEdAAIOAAgKMhkNEQBCAgAOAAgKMhkNEQBCAgAAAA==.Anthia:BAAANQAECgQIBQAAAA==.Anthreas:BAAANQAECgMIAwABNQAECggIHgANAEkjAA==.Anthreax:BAABNQAECoEeAAMNAAgKSSNEEQAPAwANAAgKSSNEEQAPAwAPAAEKKhymvgBMAAAAAA==.',
Ap='Applepie:BAABNQAECoEeAAMQAAkKqxluSACVAgAQAAkKbBluSACVAgARAAEKVRoaYgA1AAAAAA==.Apretzel:BAAANQAECgIIAgAAAA==.',
Ar='Aredstrasza:BAAANQABCgQIBAAAAA==.Ares:BAAANQAECgMIBQABNQABCgYIBgAHAAAAAA==.Armous:BAABNQAECoEeAAINAAgKhBy/IgCHAgANAAgKhBy/IgCHAgAAAA==.Arms:BAACNQAFFIEHAAIMAAQKCRBvFwAlAQAMAAQKCRBvFwAlAQA1AAQKgSEAAgwACQqdHvVDAKUCAAwACQqdHvVDAKUCAAAA.Arrano:BAAANQAECgEIAQAAAA==.Arterios:BAAANQADCgQIBAAAAA==.',
As='Astrada:BAAANQAECgUIBwAAAA==.',
Aw='Awadetanga:BAAANQAECgMIAwAAAA==.',
Ay='Ayangat:BAABNQAECoEeAAISAAkKXh32IQDBAgASAAkKXh32IQDBAgABNQAFFAYIEQAOAEobAA==.Aycekween:BAAANQAECgEIAQAAAA==.',
Az='Azgar:BAAANQAECgQIBAAAAA==.Azusa:BAABNQAECoEhAAIKAAkKdBJhkABDAgAKAAkKdBJhkABDAgAAAA==.Azzulaa:BAABNQAECoEWAAMGAAcKHwc+jwBNAQAGAAcKHwc+jwBNAQASAAYKHw2YnAARAQAAAA==.',
Ba='Bacon:BAAANQAECggICAAAAA==.Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCggIGAAAAA==.Baleful:BAAANQADCgYIBgAAAA==.Ballsnipper:BAAANQADCgQIBAABNQAECggIHAATAJobAA==.',
Bb='Bbwlatinas:BAAANQAECgQIBAAAAA==.',
Be='Belgarrion:BAAANQADCgYIBQAAAA==.Belladonna:BAABNQAECoErAAMIAAkKKCJMLgC0AgAIAAgKIyJMLgC0AgAUAAYKsRtVEwDNAQABNQAFFAgIGwAIABwYAA==.Bezirk:BAABNQAFFIEIAAIVAAUKuhS7BgC6AQAVAAUKuhS7BgC6AQAAAA==.',
Bh='Bhaal:BAABNQAECoEnAAIPAAkKWh8jHADHAgAPAAkKWh8jHADHAgAAAA==.',
Bi='Bidoof:BAAANQAECgMIBQAAAA==.Bigboyfriend:BAAANQADCggICAAAAA==.Bigbubblz:BAAANQADCgYIBgAAAA==.Bighunters:BAAANQAECgQICAABNQAECgkJMwAKAO8iAA==.Bigitaly:BAAANQAECgUIEQAAAA==.Bigstix:BAAANQADCgMIAwAAAA==.Bitemarkstwo:BAAANQADCgQJBgAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAABNQAECoEfAAIWAAgKZwSuOQBUAQAWAAgKZwSuOQBUAQAAAA==.Bleedlife:BAABNQAECoEiAAMTAAkKcR2tAgAqAwATAAkKcR2tAgAqAwAMAAYKABNjtQBoAQABNQAECgkJJgAXAJUZAA==.Blindguard:BAABNQAECoEjAAILAAgKORRHEQDkAQALAAgKORRHEQDkAQAAAA==.Blinksoncd:BAABNQAECoEfAAIJAAkKCiF6AwDrAgAJAAkKCiF6AwDrAgAAAA==.Bloodrainer:BAABNQAECoEfAAIQAAgK9h+/OQDGAgAQAAgK9h+/OQDGAgAAAA==.Blutregen:BAAANQADCgUICAABNQAECggIGQAVALcIAA==.Blutzappel:BAAANQADCgIIAgABNQAECggIGQAVALcIAA==.',
Bo='Bobfriskit:BAAANQADCgYIBgABNQAECgkJJwAYAJ0ZAA==.Bonehoof:BAAANQADCgQIBAAAAA==.Bookko:BAAANQAECgQIBAABNQAFFAMIBwAZAC8JAA==.Boot:BAAANQAECgMIBQABNQAECgkJGQAaAA4HAA==.Bootkin:BAABNQAECoEZAAIaAAkKDgdJTACIAQAaAAkKDgdJTACIAQAAAA==.Borgorn:BAEBNQAECoEZAAIMAAkKiwsoggDyAQAMAAkKiwsoggDyAQAAAA==.Bownes:BAAANQAECgcIEAAAAA==.',
Br='Braedron:BAAANQAECgQIBAABNQAECgkJIAAEAE4fAA==.Brambless:BAAANQADCgUIBQAAAA==.Bramblez:BAAANQAECgYICQABNQAFFAUIDAABAEsjAA==.Breakfast:BAABNQAECoEpAAIEAAkKzSP/AgCbAwAEAAkKzSP/AgCbAwAAAA==.Brewbott:BAABNQAFFIEJAAIbAAUKPRSGBgBnAQAbAAUKPRSGBgBnAQAAAA==.Brewhal:BAAANQADCgcJBwAAAA==.Brickp:BAABNQAECoEaAAIZAAgK7hciPABWAgAZAAgK7hciPABWAgAAAA==.Brimscythe:BAAANQAECgMIAwAAAA==.',
Bu='Bubbleoseven:BAAANQADCgYIBgAAAA==.Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgQIDAAAAA==.Buroode:BAABNQAECoEZAAMVAAgKtwiqkwCvAQAVAAcKbgmqkwCvAQAcAAcKugQHCgBJAQAAAA==.Busselton:BAAANQAECggIEAAAAA==.',
Bv='Bvngly:BAACNQAFFIENAAIdAAUKghTJBgCJAQAdAAUKghTJBgCJAQA1AAQKgS4AAh0ACQowItwGAFwDAB0ACQowItwGAFwDAAAA.',
['Bè']='Bèat:BAACNQAFFIEGAAIeAAUKFwrgAQAaAQAeAAUKFwrgAQAaAQA1AAQKgRgABB4ACQoiG+8EAMECAB4ACQoiG+8EAMECAB0ABQrdBDtIANwAAB8AAQrKAyyJACkAAAAA.',
['Bø']='Børedom:BAAANQAECgEIAQAAAA==.',
Ca='Cakeshifter:BAAANQAECgcICAAAAA==.Callister:BAABNQAECoE+AAIMAAgKuAdfpgCRAQAMAAgKuAdfpgCRAQAAAA==.Campanda:BAAANQAECgEIAQAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgQIBgAAAA==.',
Ce='Cellwynn:BAAANQADCgQICAAAAA==.',
Ch='Champthyr:BAABNQAECoElAAMgAAkKNBTaBwD6AQAgAAgKFRTaBwD6AQAhAAkKawxPFADpAQAAAA==.Chaosblt:BAABNQAECoEXAAMIAAkKrBz0LAC5AgAIAAkKrBz0LAC5AgAUAAIK+gV0XwBcAAAAAA==.Charmander:BAAANQADCgQIBAAAAA==.Cherwòòd:BAAANQABCgIIAgAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clobberela:BAAANQADCggIEAAAAA==.Clouds:BAAANQAECgcIEAAAAA==.',
Co='Coachkreeton:BAABNQAECoEsAAMLAAkKmB9nCwBaAgAMAAkKqBsKRgCfAgALAAcK3x5nCwBaAgAAAA==.Cocopie:BAAANQADCgMIBAAAAA==.Cologa:BAAANQAECggIDwAAAA==.Confess:BAABNQAECoEcAAICAAgKnhPOXADbAQACAAgKnhPOXADbAQAAAA==.Coola:BAABNQAECoEZAAIiAAcK+x0sDQCBAgAiAAcK+x0sDQCBAgAAAA==.Coollá:BAAANQADCggIEgABNQAECgcIGQAiAPsdAA==.Coot:BAAANQAECgEIAgAAAA==.Copdk:BAAANQAECgIIAgABNQAFFAEIAQAHAAAAAA==.Cophardar:BAAANQAECgMIAwABNQAFFAEIAQAHAAAAAA==.Copmage:BAAANQAFFAEIAQAAAA==.Cosecants:BAAANQAECgQIBAABNQAECgkJIwASAEEZAA==.Cosines:BAABNQAECoEjAAMSAAkKQRk7MAB6AgASAAgK9xs7MAB6AgAGAAgKJhsPSQAmAgAAAA==.Cowculated:BAABNQAECoEcAAMTAAgKmhvVCAApAgATAAYKQiDVCAApAgAMAAYKjA70uQBbAQAAAA==.Cowsrule:BAAANQAECgcIEwAAAA==.',
Cr='Crestfallen:BAAANQADCgUICAAAAA==.Criselpriest:BAAANQADCgcIBwAAAA==.Critt:BAAANQAECgcICQABNQAECgkJIgASAMQiAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQAECgUICAAAAA==.Darkaunnas:BAABNQAECoEbAAIiAAgK6h5JCQDPAgAiAAgK6h5JCQDPAgAAAA==.Darth:BAABNQAECoEeAAILAAgKahVLEQDkAQALAAgKahVLEQDkAQAAAA==.Darwinism:BAAANQADCggJCgAAAA==.Daydayy:BAAANQAECggIDgAAAA==.',
De='Deathchamp:BAAANQAECgQIBAABNQAECgkJJQAgADQUAA==.Deathnought:BAAANQADCgYJBgAAAA==.Declan:BAAANQAECgUIBwAAAA==.Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQAECgEJAQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demoncore:BAAANQADCggICAABNQAECggIFgAMALEWAA==.Demonetizer:BAACNQAFFIEOAAIfAAUKkxopBwCfAQAfAAUKkxopBwCfAQA1AAQKgTQAAh8ACQqhJXECAMYDAB8ACQqhJXECAMYDAAAA.Demonicart:BAAANQADCgUIBQABNQAECggIHQANAPofAA==.Demyxx:BAAANQAECgQJCgAAAA==.Denniecrane:BAECNQAFFIEJAAMSAAUKERitDABWAQASAAQK1BWtDABWAQAGAAEKzAJMLQA9AAA1AAQKgR4AAxIACQqZGck4AFQCABIACQqZGck4AFQCAAYAAQrLEhkLAT4AAAAA.Dex:BAAANQADCgIIAgAAAA==.',
Df='Dfa:BAAANQADCgUIBQABNQAECgUIDwAHAAAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAwAAAA==.',
Di='Dirtywork:BAABNQAECoEjAAIMAAkKux0WKgABAwAMAAkKux0WKgABAwAAAA==.',
Dm='Dmnikki:BAAANQADCggIEQAAAA==.',
Do='Dockside:BAAANQADCgMIAwAAAA==.Domiknight:BAAANQADCggIEAAAAA==.Dominic:BAAANQADCgQIBwAAAA==.Domise:BAAANQADCgQICAAAAA==.Donttrustme:BAABNQAECoEcAAMSAAgKIR3PLQCGAgASAAgKIR3PLQCGAgAGAAYKDBcMcwCYAQAAAA==.',
Dr='Drae:BAAANQAECgQIDQAAAA==.Dragunass:BAAANQAECgIIAgAAAA==.Drama:BAAANQABCgMIBAAAAA==.Dravenmurdok:BAAANQABCgEIAQAAAA==.Drayu:BAAANQAECgEIAQAAAA==.Drazhar:BAAANQAECgcIBwAAAA==.Drexl:BAAANQAFFAEIAgABNQAFFAUIDwALAEYQAA==.',
['Dé']='Dév:BAAANQADCgIIAgAAAA==.',
Ea='Earthquake:BAAANQADCgIIAwAAAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQAECgYIEwAAAA==.Eliardis:BAAANQADCggIFwAAAA==.Elizabetta:BAAANQAECgMJAwAAAA==.Ellwine:BAAANQADCgYIBgAAAA==.Elystravia:BAAANQAECgUIBQABNQAECggIHAASACEdAA==.',
Em='Emmahotson:BAAANQAECggIBwABNQAECggIGgAbAPIXAA==.Emrys:BAABNQAECoEbAAISAAgKwCI1FQAKAwASAAgKwCI1FQAKAwAAAA==.',
En='Enigmazz:BAAANQAECgIJAwAAAA==.',
Ep='Epictitus:BAAANQAECgIIAgAAAA==.',
Es='Escaflowne:BAACNQAFFIESAAMQAAUKjBsIBwC2AQAQAAUKjBsIBwC2AQARAAIKlAsJCwBsAAA1AAQKgTIAAhAACQpQJtkDANcDABAACQpQJtkDANcDAAAA.Escanór:BAAANQADCgQIBAAAAA==.',
Et='Eternity:BAAANQAECgIIAgABNQAECgkJFgAQAFIIAA==.Ethaee:BAAANQADCggIEwAAAA==.',
Eu='Euli:BAAANQAECggIEAABNQAFFAYIGgANANcaAA==.Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCggIGgAAAA==.',
Ex='Exit:BAAANQAECgYIEwAAAA==.Extermine:BAAANQAECgEIAQAAAA==.',
Ey='Eyks:BAAANQAECgEIAQAAAA==.',
Fa='Faelithndrel:BAAANQAECgUIDwAAAA==.Farmette:BAABNQAECoEYAAIIAAcK5hIhgAC5AQAIAAcK5hIhgAC5AQAAAA==.Fatherfloop:BAAANQAECgIIAwAAAA==.',
Fe='Felbeard:BAACNQAFFIEbAAQIAAgKHBg4AwApAgAIAAYKrBk4AwApAgAUAAIKqBgQBwC2AAABAAEKVAEiCABVAAA1AAQKgSoAAwgACQoBJv4MAFIDAAgACAorJv4MAFIDABQABwpUFaoQAOwBAAAA.Feleâ:BAAANQAECgQICwAAAA==.Ferreday:BAABNQAECoEbAAILAAcK8Ro3DgAdAgALAAcK8Ro3DgAdAgAAAA==.Fewix:BAAANQABCgIIAgAAAA==.',
Fi='Fingoflin:BAAANQAECgYIBgAAAA==.Firechicken:BAAANQAECgQICQAAAA==.Firemystic:BAAANQAECgEIAQAAAA==.Fivemagics:BAAANQAECgMIAwAAAA==.',
Fl='Flamereaper:BAAANQADCgYIBgABNQAECggIKQAKAPEYAA==.Fleakertwo:BAACNQAFFIEMAAIEAAUKdQI0CABKAQAEAAUKdQI0CABKAQA1AAQKgS4AAgQACQpgFqgWAKECAAQACQpgFqgWAKECAAAA.Fleischwolf:BAAANQADCggICAAAAA==.Flifaline:BAAANQAECgYIBgAAAA==.Floopzii:BAABNQAECoElAAIZAAgKKSVkDABXAwAZAAgKKSVkDABXAwAAAA==.Flói:BAAANQAECgcICAAAAA==.',
Fr='Friedrib:BAACNQAFFIEPAAIaAAUKGhP5CwB9AQAaAAUKGhP5CwB9AQA1AAQKgTUAAxoACQr/IkwKAG4DABoACQr/IkwKAG4DACMAAwreEm5IAL8AAAAA.Frostlas:BAAANQABCgQIBgAAAA==.Frostshok:BAAANQADCggICAAAAA==.',
Fu='Fulldipey:BAABNQAECoEeAAQkAAgKlgoQIgCbAQAkAAgKlgoQIgCbAQAhAAUKxxILIAA4AQAgAAEK3QrhIAAvAAAAAA==.Furrythot:BAACNQAFFIELAAINAAMK3B8tEQAQAQANAAMK3B8tEQAQAQA1AAQKgTYAAg0ACQp1JCAEAKgDAA0ACQp1JCAEAKgDAAAA.Fuzeewuzee:BAEANQAECgUIBQABNQAFFAUICQASABEYAA==.',
Ga='Galise:BAAANQAECgQIDQAAAA==.Galynnia:BAAANQADCgYICgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAABNQAECoEmAAIWAAkKxxR9IQAjAgAWAAkKxxR9IQAjAgAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQAECgQIDAAAAA==.Gildeath:BAACNQAFFIEJAAINAAUKTRojCQCdAQANAAUKTRojCQCdAQA1AAQKgRUAAg0ACAqcIdEcALECAA0ACAqcIdEcALECAAAA.Gimlie:BAABNQAECoEkAAIcAAkKcg0sBQBIAgAcAAkKcg0sBQBIAgAAAA==.Gimmix:BAAANQAECgcIEgABNQAECgkJJAAcAHINAA==.',
Go='Gobbylynn:BAACNQAFFIELAAIDAAQKchzyBwBeAQADAAQKchzyBwBeAQA1AAQKgS0AAwMACQp0JNwGAFsDAAMACQp0JNwGAFsDAAIAAgpQDvrKAH0AAAE1AAUUBggWAAQACxwA.Gooptoob:BAAANQAECgYIDwAAAA==.Goosetits:BAAANQAECggICQAAAA==.',
Gr='Grider:BAAANQADCggIFgAAAA==.Grogosh:BAAANQADCgYIBgAAAA==.Grumpy:BAAANQABCgQIBAAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.Gulog:BAAANQADCgMIAwAAAA==.Guzzlord:BAAANQADCgYIBgAAAA==.',
Gw='Gwendolen:BAAANQAECggICAABNQAECggIGwASAMAiAA==.',
Ha='Hagran:BAAANQADCggIEQAAAA==.Haint:BAABNQAECoEcAAIKAAgKdB/pXACzAgAKAAgKdB/pXACzAgAAAA==.Halzak:BAAANQAECgEJAgAAAA==.Harambeisbae:BAAANQAECgcIDwAAAA==.Harmön:BAAANQAECgMIBgAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCggIBgAHAAAAAA==.',
He='Healah:BAAANQADCgcIBwABNQAECgcIHwAfAKcdAA==.Hegotthedrip:BAACNQAFFIEQAAMUAAUKtxbTBQC/AAAIAAMKsRC6HADhAAAUAAIKwB/TBQC/AAA1AAQKgRwABBQACQoCH/0LACwCABQABwqvHf0LACwCAAgABgrPHEF+AL4BAAEAAQpfB0soAD4AAAAA.Helios:BAABNQAECoEgAAMQAAkKcCJXKwD9AgAQAAkKyiFXKwD9AgARAAUKzxsGKQBpAQABNQABCgYIBgAHAAAAAA==.Hellaquin:BAACNQAFFIEIAAIDAAMKYh1oCgAVAQADAAMKYh1oCgAVAQA1AAQKgSsAAgMACQoOJTQEAIgDAAMACQoOJTQEAIgDAAAA.Hellomotojr:BAABNQAECoEgAAIVAAgKqBzONACqAgAVAAgKqBzONACqAgAAAA==.',
Hi='Hijackx:BAAANQAECggIHQAAAQ==.Hinotama:BAAANQADCggIEAAAAA==.',
Ho='Holdne:BAABNQAECoEfAAIQAAgKkRCLjgDUAQAQAAgKkRCLjgDUAQAAAA==.Holycanolii:BAAANQADCgIIAgAAAA==.Holycoward:BAAANQAECgcICgAAAA==.Holynova:BAABNQAECoEfAAMlAAgKdx7jAgDBAgAlAAgKdx7jAgDBAgACAAEKnAtd3QA+AAAAAA==.Holypoker:BAAANQAECgYIEQAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQAECgUICAAAAA==.Horux:BAAANQADCggIHwAAAA==.',
Hr='Hrothgar:BAAANQAECggICAAAAA==.',
Hu='Humanpaladin:BAEBNQAFFIEGAAIQAAYKJAnnBwCkAQAQAAYKJAnnBwCkAQAAAA==.',
Hy='Hyhu:BAABNQAECoEkAAMWAAkKmxlPJgD4AQAVAAYKjhxfcQABAgAWAAgKBhdPJgD4AQAAAA==.Hymlok:BAABNQAECoElAAIUAAgK6AkYGgCUAQAUAAgK6AkYGgCUAQAAAA==.Hymnsorrow:BAAANQADCgYIBgABNQAECggIIQAfAD4bAA==.Hyperion:BAABNQAECoEWAAIQAAkKUgi4qwCPAQAQAAkKUgi4qwCPAQAAAA==.Hyuga:BAAANQAECgYIEgAAAA==.',
Ic='Iccarium:BAABNQAFFIEGAAIPAAQK4BC2CwAoAQAPAAQK4BC2CwAoAQAAAA==.Icexjh:BAAANQAECgQIDwAAAA==.',
Ig='Ignatowski:BAAANQAECgQICAAAAA==.Igorongon:BAABNQAECoEcAAIPAAcKWRCuWwB6AQAPAAcKWRCuWwB6AQAAAA==.',
Ii='Iindulgelag:BAAANQAECgQIBAAAAA==.',
Ik='Ikhawe:BAAANQAECgIIAgAAAA==.',
Im='Imgunagetya:BAAANQADCgQIBAAAAA==.',
In='Inebrious:BAAANQAECgQIDgAAAA==.Insplictus:BAAANQADCggIEAAAAA==.',
Io='Ionna:BAAANQADCggICgABNQAECggIHwAbAJkVAA==.',
Ir='Ironmann:BAAANQAECgUJEQAAAA==.',
It='Itsmäam:BAABNQAECoEiAAISAAkKxCKYCABrAwASAAkKxCKYCABrAwAAAA==.',
Iw='Iwixl:BAAANQADCgEIAQAAAA==.',
Ja='Jabadin:BAAANQAECgQJBAAAAA==.Jabamental:BAACNQAFFIELAAISAAQKTReUDABYAQASAAQKTReUDABYAQA1AAQKgSoAAhIACQrbJEkGAIMDABIACQrbJEkGAIMDAAAA.Jaded:BAAANQAECgQICgAAAA==.Jadefonda:BAABNQAECoEaAAIbAAgK8heCGgA/AgAbAAgK8heCGgA/AgAAAA==.Jamx:BAACNQAFFIEHAAMUAAQKEANHEACHAAAUAAIKLgNHEACHAAAIAAIK8gJULwB6AAA1AAQKgSEABAgACQo1GrdqAPYBAAgABwpXFrdqAPYBABQAAwopFro0AOQAAAEAAgoeG50YAKIAAAE1AAQKCQkmABUAFCEA.Jamy:BAABNQAECoEmAAMVAAkKFCGPQQCBAgAVAAgKpSOPQQCBAgAWAAgKWBdiJwDvAQAAAA==.Jamzs:BAAANQADCgIIAgABNQAECgkJJgAVABQhAA==.Jandria:BAABNQAECoElAAICAAgK6SDDGwDrAgACAAgK6SDDGwDrAgAAAA==.Janos:BAACNQAFFIELAAIbAAYKdxVZBADGAQAbAAYKdxVZBADGAQA1AAQKgRgAAhsACQqkInMNAOoCABsACQqkInMNAOoCAAAA.Jashin:BAABNQAECoEkAAMVAAkKyiPTBQCnAwAVAAkKyiPTBQCnAwAWAAMKVBviRwDqAAAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAABNQAECoEfAAQUAAkKrB38HgBuAQAIAAkKchhITwBGAgAUAAUKHxz8HgBuAQABAAMK3iG2FADTAAAAAA==.',
Je='Jerm:BAAANQAECgQIBQAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAABNQAECoEgAAMQAAgKFgtIoQCnAQAQAAgKFgtIoQCnAQAZAAUK0wTkwgDNAAAAAA==.',
Jo='Joobi:BAABNQAECoEYAAIVAAYKPB+lcgD+AQAVAAYKPB+lcgD+AQAAAA==.Jorrethoi:BAABNQAECoEYAAIjAAcK0x1TGABVAgAjAAcK0x1TGABVAgAAAA==.Jovar:BAAANQAECgIIAgAAAA==.',
Ju='Jurble:BAABNQAECoEgAAIEAAkKTh93DQD7AgAEAAkKTh93DQD7AgAAAA==.Juurou:BAAANQADCggJGQAAAA==.',
Jy='Jynn:BAAANQAECgUIDwAAAA==.',
['Jä']='Jäydedfäith:BAAANQAECgQJBAAAAA==.',
Ka='Kabbu:BAABNQAECoEkAAIaAAkKwiLsFAAJAwAaAAkKwiLsFAAJAwAAAA==.Kaelord:BAAANQAECgYIBgAAAA==.Kaila:BAAANQADCgEIAQAAAA==.Kaimed:BAABNQAECoEzAAMKAAkK7yL0EQCGAwAKAAkK7yL0EQCGAwAJAAIKIiGtIgC1AAAAAA==.Kaizer:BAECNQAFFIELAAIfAAQKax/sBwCKAQAfAAQKax/sBwCKAQA1AAQKgSUAAh8ACQp3JCkEAKYDAB8ACQp3JCkEAKYDAAAA.Kakkarot:BAAANQAECgIIAgAAAA==.Kalrakin:BAAANQAECgIIAgABNQAECgkKKQAEAM0jAA==.Kamton:BAAANQAECgMIBAAAAA==.Kanïka:BAAANQADCgQIBAAAAA==.Kardrig:BAAANQAECgUICQAAAA==.Katwoman:BAABNQAECoEtAAIjAAkKxhxuDgDPAgAjAAkKxhxuDgDPAgAAAA==.Kaylana:BAAANQAECgUICAAAAA==.',
Kd='Kdzee:BAAANQADCggJEwAAAA==.',
Ke='Keicus:BAAANQABCgUIAwABNQAECgEIAQAHAAAAAA==.',
Kh='Khalezzi:BAAANQAFFAIIAwAAAA==.Khonos:BAABNQAECoEfAAQUAAgKTiIxBQC+AgAUAAcK1SIxBQC+AgABAAUKCiD+CADQAQAIAAIK6R/H9gCqAAAAAA==.Khrônic:BAAANQADCgYIBgAAAA==.',
Ki='Killercold:BAAANQAECgYIDgAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAACNQAFFIEPAAIVAAUKUxixBgC7AQAVAAUKUxixBgC7AQA1AAQKgSYAAhUACQp2JB4XACYDABUACQp2JB4XACYDAAAA.',
Kl='Kloosterhuis:BAABNQAECoEoAAIQAAcKvSJHQwClAgAQAAcKvSJHQwClAgAAAA==.',
Ko='Kodoseeker:BAABNQAECoEnAAIjAAkKpBNuGABUAgAjAAkKpBNuGABUAgAAAA==.Kovos:BAAANQAECgEIAQAAAA==.Kovä:BAAANQAECgcIDAAAAA==.',
Kr='Krean:BAABNQAECoEhAAIfAAgKPhsLHgCEAgAfAAgKPhsLHgCEAgAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQAECgUIDQABNQAECgkJMAAYADUjAA==.Kunarr:BAABNQAECoEwAAIYAAkKNSPPAQCRAwAYAAkKNSPPAQCRAwAAAA==.',
Kw='Kwyte:BAAANQAECgYIEQAAAA==.',
Ky='Kylerichards:BAAANQAECgUIBwAAAA==.Kyohunt:BAABNQAECoEqAAMWAAkKnSGgDwDdAgAWAAgK/yCgDwDdAgAVAAUKbyIkoQCSAQAAAA==.Kyoknight:BAAANQAECgYIBQABNQAECgkJKgAWAJ0hAA==.Kyoshock:BAABNQAECoEYAAMSAAcKvBXpawCZAQASAAYK1xbpawCZAQAGAAcKSAtdhQBmAQABNQAECgkJKgAWAJ0hAA==.',
La='Ladonda:BAAANQADCgYICAAAAA==.Lanius:BAAANQADCgYICgAAAA==.Lanyx:BAAANQADCgYIDAAAAA==.Lareina:BAACNQAFFIEOAAIGAAUKfAhTDABuAQAGAAUKfAhTDABuAQA1AAQKgTIAAgYACQpwHtcbAAoDAAYACQpwHtcbAAoDAAAA.Lareith:BAAANQADCgIIAgAAAA==.Larinara:BAAANQAECgEIAQAAAA==.Laziness:BAAANQAFFAEIAQABNQAECgIIAgAHAAAAAA==.',
Le='Lemonhope:BAAANQAECgcIDwAAAA==.',
Li='Lightnights:BAAANQADCggIDgAAAA==.Lilmerlin:BAAANQADCggIDwAAAA==.Linchknight:BAABNQAECoEWAAIPAAcKdRHYWACGAQAPAAcKdRHYWACGAQAAAA==.Littlefudger:BAAANQABCgIIAgAAAA==.Livola:BAABNQAECoEYAAIQAAgKtBgKZwA5AgAQAAgKtBgKZwA5AgAAAA==.',
Lo='Locknik:BAAANQADCgYIDwAAAA==.Locktooth:BAAANQAECgcICAAAAA==.Loka:BAAANQADCggICAABNQAECggIHAASACEdAA==.Lokkahn:BAAANQADCggIGwAAAA==.',
Lu='Lucentio:BAAANQAECgEIAQABNQAECgUIEQAHAAAAAA==.Lunarsol:BAABNQAECoEiAAIaAAgK6RiwLABSAgAaAAgK6RiwLABSAgAAAA==.',
Ly='Lyanna:BAAANQAECgEIAQABNQAECgkJJAAcAHINAA==.',
['Lä']='Lätêx:BAACNQAFFIELAAIQAAQK0SXQBgC7AQAQAAQK0SXQBgC7AQA1AAQKgSwAAhAACQrHJjQDAN0DABAACQrHJjQDAN0DAAAA.',
Ma='Magicmeatxxl:BAAANQAECgUICwAAAA==.Magusgobrr:BAABNQAECoEnAAIKAAgK4iXwHgBUAwAKAAgK4iXwHgBUAwAAAA==.Mahawker:BAAANQAECgQICQAAAA==.Mahfaty:BAAANQAECgEIAQAAAA==.Makellos:BAAANQADCgcIBwAAAA==.Marcus:BAAANQAECgIIAgABNQAFFAIIAgAHAAAAAA==.Marideous:BAAANQAECgQICAAAAA==.Mark:BAAANQAECgEIAQABNQAFFAIIAgAHAAAAAA==.Marth:BAABNQAECoEXAAIQAAcKzRHmpgCaAQAQAAcKzRHmpgCaAQAAAA==.Mashem:BAABNQAECoEfAAMKAAkKCxw+aQCXAgAKAAkKDxs+aQCXAgAJAAEKxx2bNgBKAAAAAA==.Mathias:BAAANQAECgUIBwAAAA==.Mattpriest:BAACNQAFFIEQAAICAAUK+R4qCADmAQACAAUK+R4qCADmAQA1AAQKgTIABAIACQqcIyUTAB0DAAIACQqcIyUTAB0DACUABApVGX8SAOYAAAMAAgp8HeNRAJsAAAAA.Maxverclappn:BAAANQAECgUIDgAAAA==.Maxvertrappn:BAABNQAECoE1AAIVAAkK1CXcAQDjAwAVAAkK1CXcAQDjAwAAAA==.',
Mc='Mcsloppy:BAAANQAECggIDAAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAFFAUIDwAaABoTAA==.Methicillin:BAAANQADCggICgAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAABNQAECoEWAAIQAAcK0w5QrgCKAQAQAAcK0w5QrgCKAQAAAA==.Milkedmoose:BAABNQAECoEeAAIQAAgKcA6gkgDKAQAQAAgKcA6gkgDKAQAAAA==.Milkers:BAACNQAFFIEJAAIKAAQK4Rq6HQBZAQAKAAQK4Rq6HQBZAQA1AAQKgSYAAgoACQpkIoIxAB0DAAoACQpkIoIxAB0DAAAA.Minimoose:BAABNQAECoEfAAIfAAgKUhLZLwD5AQAfAAgKUhLZLwD5AQAAAA==.Misclick:BAAANQAECgMIAwABNQAECggIJgABAHgQAA==.',
Mo='Moistymonk:BAAANQADCgEIAQAAAA==.Monday:BAAANQADCggICwAAAA==.Moona:BAABNQAECoEkAAIdAAkKWyQmAgC7AwAdAAkKWyQmAgC7AwAAAA==.Moonberry:BAAANQAECggIEAAAAA==.Moonlock:BAAANQADCggIHwAAAA==.Moosby:BAAANQAECgQIBAAAAA==.Morissa:BAAANQADCgQJBQAAAA==.Motomotoo:BAAANQAECgQIDgAAAA==.',
Mu='Muffinfeliz:BAAANQAECgQICgAAAA==.',
My='Myriad:BAAANQAECgYIBwABNQAFFAcIEwAhAE8dAA==.Mythundreran:BAAANQAECgQIDgAAAA==.',
['Mà']='Màyhém:BAAANQAECgUIBQAAAA==.',
Na='Namdari:BAABNQAECoEfAAICAAgKIhDAYgDFAQACAAgKIhDAYgDFAQAAAA==.Nanahammer:BAAANQADCgEIAQAAAA==.Nanasquirts:BAAANQADCgEIAQABNQAFFAEIAQAHAAAAAA==.Natymz:BAAANQABCgQIBAAAAA==.Nazzan:BAAANQAECgEIAgABNQAECgkJLQAGAOwhAA==.',
Ne='Neaera:BAAANQAECgIIAgAAAA==.',
Ni='Nighthaven:BAAANQADCgIIAgAAAA==.Nightmàre:BAAANQAECgEIAQAAAA==.Nightshade:BAABNQAECoEYAAMmAAgKuxusBQByAgAmAAcKDx2sBQByAgAEAAEKcRJahQA+AAABNQAFFAMICAADAGIdAA==.Nightstride:BAAANQAECgIIAgAAAA==.Nikkô:BAAANQABCgQJCAAAAA==.Niksi:BAAANQADCgQIBgAAAA==.Nirra:BAABNQAECoEWAAISAAcKigsQiwBAAQASAAcKigsQiwBAAQAAAA==.Niso:BAAANQAECgQICAAAAA==.',
No='Noatt:BAAANQADCgMIAwAAAA==.Nokona:BAAANQADCgEJAQAAAA==.Novapal:BAABNQAECoEZAAIQAAgK2BJHggDyAQAQAAgK2BJHggDyAQAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Nu='Numnumzz:BAAANQABCgQIBgAAAA==.',
Ny='Nyxirus:BAAANQADCgYICAAAAA==.',
Oc='Ochnauq:BAABNQAECoElAAINAAgKERA2TAClAQANAAgKERA2TAClAQABNQAFFAQICwAnACoIAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAABNQAECoEnAAIGAAkKax8GGAAjAwAGAAkKax8GGAAjAwAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.Orindier:BAAANQADCgYIBgAAAA==.',
Ov='Overcharged:BAAANQAECgEIAQAAAA==.',
Pa='Pada:BAABNQAECoEeAAIaAAgKvxiiLABSAgAaAAgKvxiiLABSAgAAAA==.Pakku:BAACNQAFFIEOAAIbAAUKThN1BgBqAQAbAAUKThN1BgBqAQA1AAQKgTIAAhsACQqSI/cEAHMDABsACQqSI/cEAHMDAAAA.Paladaine:BAAANQADCggIEgAAAA==.Pallix:BAAANQAECgYIDwABNQAECgkJHwAUAKwdAA==.Palpacino:BAAANQAECgYIDgABNQAECggIIwAVALkUAA==.Palytivecare:BAAANQAECgIIAgAAAA==.Papajaja:BAABNQAECoEhAAMIAAgKKx2yLwCuAgAIAAgKKx2yLwCuAgAUAAMKyxNZPADFAAAAAA==.Papal:BAAANQADCggICQAAAA==.Paramôre:BAAANQAECggICwABNQAFFAUIDwASAM0cAA==.',
Pe='Peace:BAAANQAECggIEAABNQAFFAIIAgAHAAAAAA==.Peachmangos:BAAANQAECgUIBgAAAA==.Peachpanther:BAAANQADCgYIBgAAAA==.Pegmianis:BAABNQAECoEbAAMPAAcK+iKcHQC8AgAPAAcK2SKcHQC8AgANAAYKGSHSLwA2AgAAAA==.Percivál:BAAANQAECggIDwABNQAECgkJNQAVANQlAA==.Peseant:BAEANQADCggICAABNQAFFAYIBgAQACQJAA==.',
Ph='Phatsword:BAAANQAECgIIAgAAAA==.Phigon:BAAANQAECgcIDgAAAA==.',
Pi='Piikarogue:BAAANQAECgQIBAAAAA==.Pinknmoist:BAAANQAECgQIEQAAAA==.Pixelbaddy:BAAANQADCggIIAAAAA==.',
Pl='Plumbus:BAAANQADCggIDQAAAA==.',
Po='Polygrip:BAAANQAECgYIDwAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Pr='Praxtintar:BAAANQAECgYICwAAAA==.Providencia:BAAANQAECgYIEQAAAA==.Pru:BAAANQABCgIIAgAAAA==.Prushammie:BAAANQABCgIIAgAAAA==.Prutank:BAAANQABCgEIAQAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQABNQAECgUICwAHAAAAAA==.',
Pu='Pure:BAACNQAFFIEGAAIZAAIKOyE4FgDGAAAZAAIKOyE4FgDGAAA1AAQKgRsAAhkACQrxIVUJAHEDABkACQrxIVUJAHEDAAAA.Purman:BAAANQADCgYIFQAAAA==.',
Py='Pyrine:BAAANQAECgUIEQAAAA==.',
Qu='Quanchnauq:BAAANQAECggIEQABNQAFFAQICwAnACoIAA==.Quancho:BAACNQAFFIELAAInAAQKKgg8AwDyAAAnAAQKKgg8AwDyAAA1AAQKgTcAAicACQpXGukJAJwCACcACQpXGukJAJwCAAAA.',
Qw='Qwade:BAAANQAECgEIAQAAAA==.',
Ra='Radishes:BAAANQADCgUIBwAAAA==.Ragran:BAAANQADCggIKAAAAA==.Rakaman:BAABNQAECoEZAAMMAAgKtBDWggDwAQAMAAgKlBDWggDwAQATAAQKQgkzHADDAAAAAA==.Ramza:BAACNQAFFIEXAAIQAAcKSR+YAADKAgAQAAcKSR+YAADKAgA1AAQKgSgAAhAACQp1JhEGAMADABAACQp1JhEGAMADAAAA.Ranbou:BAACNQAFFIELAAIKAAQKQQgLJAAmAQAKAAQKQQgLJAAmAQA1AAQKgSwAAwoACQqFIHI+APsCAAoACQqFIHI+APsCACgABAofFIwFAP4AAAAA.Randor:BAAANQABCgQIBgAAAA==.Rashka:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.Ratatasquer:BAABNQAECoEfAAIbAAgKmRUEIAABAgAbAAgKmRUEIAABAgAAAA==.Rattleballs:BAAANQAECgYIDgABNQAECgcIDwAHAAAAAA==.',
Re='Reaverpie:BAAANQAECgQIBgAAAA==.Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQAECgQIBgAAAA==.Repens:BAAANQAECgYIEwAAAA==.Restosterone:BAABNQAECoEaAAISAAkKGR3iHADdAgASAAkKGR3iHADdAgAAAA==.Ret:BAAANQAECgQIBwABNQAFFAQIBwAMAAkQAA==.Retbeanznrce:BAAANQAECgYIDQAAAA==.Retful:BAAANQADCgUIBQABNQAFFAUIDgAfAJMaAA==.Revo:BAAANQADCgYIBgABNQAFFAMIBwAZAC8JAA==.',
Rh='Rhaid:BAABNQAECoElAAIRAAgKLCO/BgAjAwARAAgKLCO/BgAjAwAAAA==.Rhordrick:BAABNQAECoEYAAIIAAcKJRrBYAATAgAIAAcKJRrBYAATAgAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQAECgEIAQAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCggIHwAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Roughstuff:BAAANQADCgEJAQAAAA==.Rowdi:BAAANQADCggIDAAAAA==.',
Ru='Rubmybelly:BAAANQADCggICAAAAA==.Rukarm:BAAANQADCgcIHAAAAA==.Runawaynow:BAACNQAFFIEWAAISAAcK0hReAgBlAgASAAcK0hReAgBlAgA1AAQKgSYAAhIACQriIXQUABADABIACQriIXQUABADAAAA.Runelife:BAABNQAECoEmAAIXAAkKlRmDHACAAgAXAAkKlRmDHACAAgAAAA==.',
Ry='Ryanadonis:BAAANQADCgUIDAAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAABNQAECoEYAAINAAcK5xllNgARAgANAAcK5xllNgARAgAAAA==.Samsara:BAAANQAECgYICgAAAA==.Saori:BAAANQAECgIIAgABNQAECgkJJAAVAMojAA==.Sartok:BAAANQAECgIIAgAAAA==.',
Sc='Scottnails:BAABNQAFFIEJAAIaAAUKFwRCEgAIAQAaAAUKFwRCEgAIAQAAAA==.',
Se='Semanin:BAAANQADCgEJAQAAAA==.Serendipity:BAAANQADCgUIBgAAAA==.Seyuri:BAABNQAECoEkAAIVAAkKqxvyJwDZAgAVAAkKqxvyJwDZAgAAAA==.Seán:BAAANQAECgYIEwAAAA==.',
Sh='Shadonine:BAAANQADCgUIBgAAAA==.Shadowar:BAAANQAECgYIEwAAAA==.Shadowbell:BAABNQAECoElAAIDAAgKJCAGEADdAgADAAgKJCAGEADdAgAAAA==.Shadowgale:BAABNQAECoEWAAQgAAcK4QmXEQDsAAAgAAYKWgaXEQDsAAAkAAEK9QJ/SgAsAAAhAAEKTwOSPQAlAAAAAA==.Shamanramen:BAAANQABCgQIBAAAAA==.Shangcheeto:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.Shantari:BAAANQAECgMIBQAAAA==.Shayrpd:BAAANQAECgUIDgAAAA==.Sheex:BAAANQAECgQIBAAAAA==.Shoobìes:BAAANQABCgUICQAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnmage:BAAANQABCgMIAwAAAA==.Sinnshifts:BAAANQAECgYIEgAAAA==.',
Sk='Skhorn:BAABNQAECoEmAAIhAAgKDR0aDACMAgAhAAgKDR0aDACMAgAAAA==.Skuûub:BAAANQAECgEIAQAAAA==.',
Sl='Slowone:BAAANQADCgUIBgABNQAECgcIGQAiAPsdAA==.Slãyer:BAABNQAECoEYAAIVAAcK6hTmdAD4AQAVAAcK6hTmdAD4AQAAAA==.',
Sm='Smallblessin:BAAANQADCgMJAwAAAA==.Smellafina:BAAANQAECgEIAQAAAA==.Smokedrib:BAAANQAECgQIBgABNQAFFAUIDwAaABoTAA==.',
Sn='Snorlock:BAAANQAECggIEwABNQAFFAQICQAKAOEaAA==.',
So='Sometymz:BAABNQAECoEcAAIOAAkK7RDYFQDwAQAOAAkK7RDYFQDwAQAAAA==.',
Sp='Spareathot:BAABNQAECoEhAAMhAAkKxRMWEAA4AgAhAAkKxRMWEAA4AgAgAAIKzwS2HQBHAAAAAA==.Speedspanker:BAABNQAECoEmAAIGAAcK/B5sNgB3AgAGAAcK/B5sNgB3AgAAAA==.Spem:BAAANQAECgEIAQABNQAFFAYIFQAPAP4WAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.Spookyivan:BAAANQAECggIAwAAAA==.',
St='Staar:BAAANQAECgIIAwAAAA==.Starboy:BAAANQADCgYIEAAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAACNQAFFIESAAMUAAUKtB41BwC1AAAIAAQKdx2mDQBvAQAUAAIK/B81BwC1AAA1AAQKgTIAAwgACQqZJZoLAFwDAAgACAqLJZoLAFwDABQABgrcHqoOAAQCAAAA.Stiliar:BAAANQAECgQIBwAAAA==.Strongdroid:BAAANQAECgYIBgAAAA==.Strángè:BAABNQAECoElAAIBAAgKQB1NAwCrAgABAAgKQB1NAwCrAgAAAA==.Stríve:BAAANQAECgIIAgAAAA==.Stêlla:BAAANQADCgQIBAAAAA==.',
Su='Substrate:BAAANQAECgYIEQAAAA==.Sugarteets:BAAANQAECgQICAABNQAECgkJIgASAMQiAA==.Sultan:BAAANQABCgcIBwABNQAECgEIAQAHAAAAAA==.Sunderthighs:BAAANQABCgYIBwAAAA==.Suramus:BAABNQAECoEmAAIZAAkK7R8rEQA0AwAZAAkK7R8rEQA0AwAAAA==.',
Sv='Svaval:BAACNQAFFIEJAAINAAUKxh8eBwDLAQANAAUKxh8eBwDLAQA1AAQKgR8AAg0ACQqZI5cKAFIDAA0ACQqZI5cKAFIDAAAA.Svavil:BAAANQAECgIIAgAAAA==.',
Sy='Syles:BAAANQAECgQIBAABNQAECggIHAAVANkQAA==.Syphon:BAABNQAECoElAAIIAAgKqyEmHwDxAgAIAAgKqyEmHwDxAgAAAA==.',
Ta='Tamedurmom:BAABNQAECoEjAAMVAAgKuRRBcwD8AQAVAAcKgxZBcwD8AQAcAAYKRA2+CACMAQAAAA==.Tarekk:BAABNQAECoElAAIPAAgK/hPRRQDbAQAPAAgK/hPRRQDbAQAAAA==.Tarewreck:BAAANQAECgQIBwAAAA==.Tariqpapi:BAABNQAECoEtAAQaAAkKNiAdDwA+AwAaAAkKNiAdDwA+AwAjAAEKwCAJYwBBAAAnAAEKwQjSVQAjAAAAAA==.Taxes:BAAANQAECgMIBAAAAA==.',
Te='Tehcjs:BAAANQADCgUIBQABNQABCgIIAgAHAAAAAA==.Tehcountess:BAABNQAECoEkAAINAAkK0hVuNAAcAgANAAkK0hVuNAAcAgAAAA==.',
Th='Tharos:BAABNQAECoEiAAISAAcKnxkjSQASAgASAAcKnxkjSQASAgAAAA==.Thebeerwiz:BAAANQADCggIBgAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thefollower:BAAANQADCgYIBwAAAA==.Thelianne:BAABNQAECoEYAAIQAAcKeg5ArgCKAQAQAAcKeg5ArgCKAQAAAA==.Thelmina:BAAANQAECgUICwAAAA==.Thepot:BAAANQAECggIDQABNQAECggIHQAHAAAAAQ==.Thermidor:BAABNQAECoEcAAIDAAgK9RVpHgAmAgADAAgK9RVpHgAmAgAAAA==.Thorps:BAABNQAECoEdAAQZAAgKwQ+bYADSAQAZAAgKwQ+bYADSAQAQAAcKYhZXkADQAQARAAEKZBY7aAAoAAAAAA==.Thragg:BAAANQADCgQIBAAAAA==.Thundarr:BAAANQABCgYIBgAAAA==.Thunderducky:BAAANQAECgQIBQABNQAECggIIwAVALkUAA==.Thunderloins:BAAANQADCgYICAABNQAECggIHAATAJobAA==.Thurstee:BAAANQAECggIEAAAAA==.',
Ti='Tibian:BAABNQAECoEhAAIjAAkKEhYQGABYAgAjAAkKEhYQGABYAgAAAA==.Tigerpalm:BAABNQAECoEcAAIOAAcKgxlnFQD3AQAOAAcKgxlnFQD3AQAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.Tinyshocker:BAAANQADCgUIBQABNQAECggIHwANAPEeAA==.',
To='Toastradamus:BAAANQAECgIIAQAAAA==.Totemlyfoxy:BAAANQAECgUIEgAAAA==.Touchedd:BAAANQADCgIIAgABNQADCgQIBAAHAAAAAA==.',
Tr='Trackker:BAAANQADCgQIBAAAAA==.Trapshotumad:BAAANQAECggIEgAAAA==.Treesdk:BAAANQAECgcIEQAAAA==.Trugs:BAABNQAECoEZAAQZAAgKExcSPgBOAgAZAAgKExcSPgBOAgAQAAEKogbCigEpAAARAAEKUweWbgAgAAAAAA==.Trugy:BAAANQABCgUIAwAAAA==.',
Tu='Tulsmi:BAAANQAECgUIBgAAAA==.Tuntunvergun:BAABNQAECoEkAAIaAAkKux0dFAARAwAaAAkKux0dFAARAwAAAA==.',
Tw='Twelvetacos:BAABNQAECoEiAAMSAAkKaR/WGwDjAgASAAkKaR/WGwDjAgAGAAEKgBFDDAE9AAAAAA==.',
Ty='Tyoka:BAAANQAECgYIDwAAAA==.Tyokå:BAAANQAECgIIAgAAAA==.Tyralde:BAABNQAECoEYAAQBAAkKUxETGwCGAAAIAAUKvxP2tQAzAQAUAAMKvAZsTACPAAABAAIKjhUTGwCGAAAAAA==.',
Ud='Udenlo:BAAANQAECgUIDwAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unclepumper:BAAANQAECgMIBAAAAA==.Unsub:BAAANQADCgEIAQABNQAFFAQICQAKAOEaAA==.',
Us='Usui:BAAANQADCgUIAQAAAA==.',
Va='Vaalkad:BAAANQADCggIDwAAAA==.Vaellian:BAAANQADCgUJCgAAAA==.Valei:BAAANQAECgcIDgAAAA==.Valvadime:BAAANQAECgUICwAAAA==.Vanstian:BAAANQAECggIDwABNQAECgQIBAAHAAAAAA==.Vantoes:BAABNQAECoEvAAMXAAkKTyRPAwCiAwAXAAkKTyRPAwCiAwANAAIKgxEVpABnAAAAAA==.Varina:BAAANQADCgIIAgAAAA==.',
Ve='Vecidus:BAAANQAECgIIAgAAAA==.Velassi:BAABNQAECoEmAAIBAAgKeBBQBwAHAgABAAgKeBBQBwAHAgAAAA==.Veldora:BAAANQAECgQICQAAAA==.Velouriuum:BAAANQADCgYJDwAAAA==.Vessra:BAAANQAECgQIBAAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAABNQAECoEgAAIZAAgKKRYDSgAgAgAZAAgKKRYDSgAgAgAAAA==.Vintari:BAAANQAECgEIAQAAAA==.Vivvyquinn:BAAANQADCgMIAwAAAA==.',
Vo='Volorren:BAABNQAECoEbAAIZAAcKUx8wMgCBAgAZAAcKUx8wMgCBAgAAAA==.Volzu:BAABNQAECoEkAAIGAAkKFCAIGAAjAwAGAAkKFCAIGAAjAwAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Warwickdavis:BAAANQADCggIIAABNQAECgUICAAHAAAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQABNQAECgkJLwAXAE8kAA==.Wessõn:BAAANQABCgQIBAAAAA==.',
Wh='Whely:BAECNQAFFIELAAILAAQKPh+XAQCNAQALAAQKPh+XAQCNAQA1AAQKgTkAAgsACQqhJjUAAP0DAAsACQqhJjUAAP0DAAAA.Whine:BAAANQADCgYIBgAAAA==.Whitegoodman:BAAANQADCggICAABNQAECggIHAAKADgfAA==.Whitegrlswag:BAAANQAECgIIAgAAAA==.',
Wi='Wilcoxx:BAACNQAFFIENAAMIAAUK8QqkFQAXAQAIAAQK/AmkFQAXAQAUAAEKxQ61GQBPAAA1AAQKgTMAAxQACQo6IGcQAO4BAAgACArNHz0uALQCABQABwp4F2cQAO4BAAAA.Wilcozz:BAAANQAECgIIBQABNQAFFAUIDQAIAPEKAA==.Wildtree:BAAANQABCgYIBAAAAA==.Wipeout:BAAANQAECgUICgAAAA==.Wipetime:BAAANQADCggIFQABNQAECgUICgAHAAAAAA==.Wirecutter:BAABNQAECoEXAAIEAAkKoxf+FgCfAgAEAAkKoxf+FgCfAgAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgkJJgAVABQhAA==.Wizurd:BAABNQAECoEnAAIKAAkKCg5ZnAAqAgAKAAkKCg5ZnAAqAgAAAA==.',
Wo='Wolfcult:BAABNQAECoEnAAIYAAkKnRlQCACJAgAYAAkKnRlQCACJAgAAAA==.Wolvgar:BAAANQAECgcIDgAAAA==.Wompstomper:BAAANQADCgEJAQAAAA==.Worcklock:BAACNQAFFIEOAAMIAAUKyRyUDQBwAQAIAAQKkx2UDQBwAQAUAAIKTBpiCACuAAA1AAQKgSAAAwgACQqCIvUcAPwCAAgACAoWIvUcAPwCABQAAgpTJSg3ANoAAAE1AAUUCAgbAAgAHBgA.',
Wr='Wrapwrap:BAABNQAECoEkAAICAAgKfR+cLACXAgACAAgKfR+cLACXAgAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wì']='Wìxÿ:BAAANQADCgcIBwAAAA==.',
['Wî']='Wîxx:BAABNQAECoEbAAIjAAkKmR0BDwDHAgAjAAkKmR0BDwDHAgAAAA==.Wîxÿ:BAAANQAECgUIBgAAAA==.',
Xe='Xestsalb:BAEBNQAECoEZAAIGAAgKSxpiOgBlAgAGAAgKSxpiOgBlAgAAAA==.',
Xy='Xythalia:BAAANQADCgQIAwAAAA==.',
Ya='Yacuto:BAAANQAECgYIBgAAAA==.Yayaoshi:BAAANQAECggIBgAAAA==.',
Yo='Yourlock:BAAANQAFFAEIAQAAAA==.',
Yr='Yrel:BAAANQAECggIDAAAAA==.',
Yu='Yuseolha:BAAANQADCggIGQAAAA==.',
Za='Zac:BAAANQAECggICQABNQAECggIEwAHAAAAAA==.Zacheeus:BAACNQAFFIEJAAIVAAQKUgxtDgA1AQAVAAQKUgxtDgA1AQA1AAQKgSoAAhUACQqtJOcCAM8DABUACQqtJOcCAM8DAAAA.Zaco:BAAANQAECggIEgABNQAECggIEwAHAAAAAA==.Zagran:BAAANQADCggIFQAAAA==.Zak:BAAANQAECggIEwAAAA==.Zalmo:BAAANQADCgIIBAABNQAECgcIGwAgAFwUAA==.Zantidious:BAAANQAECgUIDwAAAA==.Zaox:BAAANQADCggICAAAAA==.Zardragon:BAACNQAFFIEKAAIhAAQKyyXIAgDCAQAhAAQKyyXIAgDCAQA1AAQKgSwAAiEACQoZJicBALkDACEACQoZJicBALkDAAAA.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAACNQAFFIELAAMJAAQKZRZHAgDtAAAJAAMKHhVHAgDtAAAKAAEKORq4SQBbAAA1AAQKgSoAAwkACQrbJPoBAEQDAAkACQqpIvoBAEQDAAoABAqZHQAHAVsBAAAA.Zelithor:BAABNQAECoEgAAMJAAkKExjKDQCkAQAJAAYKjBrKDQCkAQAKAAUKGxSlDwFMAQAAAA==.Zephiatan:BAAANQAECgEIBQAAAA==.Zeryn:BAAANQABCgIJBAAAAA==.',
Zo='Zoosh:BAAANQAECgYIBgABNQAECgYIDwAHAAAAAA==.',
Zy='Zynalia:BAAANQADCgIIAgAAAA==.',
['Àr']='Àrcaneheart:BAABNQAECoEzAAIKAAgK+giM1QC2AQAKAAgK+giM1QC2AQAAAA==.',
['Æv']='Ævangelist:BAAANQADCgMIAwAAAA==.',
['Íg']='Ígris:BAAANQAECgIIAgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgcICwAAAA==.',
['Øz']='Øzzy:BAAANQAECgUIAgAAAA==.',
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
