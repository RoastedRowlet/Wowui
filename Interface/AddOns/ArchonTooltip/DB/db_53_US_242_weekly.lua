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

local lookup = {'Warlock-Destruction','Druid-Feral','Warrior-Arms','Priest-Shadow','Unknown-Unknown','Mage-Arcane','Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Hunter-BeastMastery','Monk-Windwalker','Paladin-Holy','Warlock-Demonology','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Warlock-Affliction','Evoker-Devastation','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Hunter-Marksmanship','Rogue-Assassination','Evoker-Augmentation','Warrior-Protection','Druid-Restoration','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Druid-Guardian','Shaman-Restoration','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Priest-Discipline','Shaman-Enhancement',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aahnna:BAAANQAECgQIBAABNQAECggIFQABAPcEAA==.',
Ab='Ababear:BAAANQAECgUIBwABNQAFFAUIBwACADEYAA==.',
Ad='Adeki:BAAANQADCgYIBgAAAA==.Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQAECgEIAQABNQAECggIFQABAPcEAA==.',
Al='Alarrius:BAABNQAECn8zAAIDAAoKWREsJQBwAQADAAoKWREsJQBwAQAAAA==.Albedö:BAAANQADCgIIAgABNQAFFAMIBwAEAOEQAA==.Algo:BAAANQAECgIIAwAAAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAAFAAAAAA==.Alithirae:BAAANQADCgYICgAAAA==.Allionys:BAABNQAECn8UAAIGAAcKFyBxYgC6AgAGAAcKFyBxYgC6AgAAAA==.Aloris:BAABNQAECn8WAAIHAAcKwB4TYwD3AQAHAAcKwB4TYwD3AQAAAA==.',
Am='Amanises:BAABNQAECn8pAAMIAAcKFCHnBwCxAQAIAAcKFCHnBwCxAQAJAAIKJgsUmABkAAABNQAECgkJIAAKAFEUAA==.Amilara:BAAANQAECgQIBwAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQAECgMIDAABNQAECgUICwAFAAAAAA==.Anania:BAAANQAECgUICwAAAA==.Andinestiri:BAABNQAECn8YAAILAAgK6QnylgDaAQALAAgK6QnylgDaAQAAAA==.Andolastrasz:BAAANQAECgQICAAAAA==.Angelic:BAAANQAECgYIDQAAAA==.Anightsong:BAAANQADCgQIBAAAAA==.',
Ao='Ao:BAABNQAECn8sAAIMAAkKMB+GDwDsAgAMAAkKMB+GDwDsAgAAAA==.',
Ap='Apotic:BAABNQAECn8hAAIJAAcKOQPAbADrAAAJAAcKOQPAbADrAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFH8MAAILAAcK5wf3CAC6AQALAAcK5wf3CAC6AQA1AAQKfyYAAgsACgpWHx4/AK0CAAsACgpWHx4/AK0CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAABNQAECn8iAAINAAcKSg8vLAAyAQANAAcKSg8vLAAyAQAAAA==.Arhianrod:BAAANQADCggICgAAAA==.Ariisa:BAAANQAECgQIBgAAAA==.Around:BAABNQAECn8XAAMOAAcK/w0KsgBsAQAOAAcKAAoKsgBsAQABAAIK1hmkEQBOAAABNQAECgoKLQAPADkRAA==.Artty:BAEANQAECgQIBAABNQAECgoKLwAQAH0lAA==.',
As='Askip:BAAANQADCgQICgAAAA==.Astrud:BAAANQAECgMIDAAAAA==.Asukka:BAABNQAECn8YAAMRAAkKPBVQkwD9AQARAAkK0RNQkwD9AQASAAQKWBUiRQDdAAAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFH8gAAITAAUKFQ6FBQAKAQATAAUKFQ6FBQAKAQA1AAQKfzkAAhMACgorIEMFAFgDABMACgorIEMFAFgDAAAA.Attenborough:BAAANQADCgYIBgAAAA==.',
Au='Augustine:BAAANQABCgIIAgAAAA==.',
Av='Avesa:BAAANQADCggIOQAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Ay='Ayyahuasca:BAAANQABCgIIAgABNQAECgYIFQAOABgGAA==.',
Az='Azazell:BAAANQADCggIEQAAAA==.Azenea:BAABNQAECn8VAAIBAAgK9wRnIQBmAQABAAgK9wRnIQBmAQAAAA==.',
Ba='Baculum:BAABNQAECn8UAAMJAAcKPRE1XAA4AQAJAAcKww41XAA4AQAQAAUKgBZBcAA0AQAAAA==.Badmoonrisin:BAAANQADCgYJCQAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Ballzach:BAAANQAECgIIAgABNQAFFAcIHgAQAB0iAA==.Bandolero:BAAANQAECgUIBQAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBQAFAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBQAFAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAABNQAECn8YAAIOAAoKvgx+QgAHAQAOAAoKvgx+QgAHAQAAAA==.',
Bi='Bigbutter:BAAANQAECgUICAAAAA==.Bittybow:BAAANQADCgQIBAAAAA==.Bittydrood:BAAANQAECgQICAAAAA==.Bittylexis:BAABNQAECn8ZAAIUAAcKIApLBAAUAQAUAAcKIApLBAAUAQAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blarcedeliu:BAAANQAECgIIAgABNQAECgYIFAAVAE4XAA==.Bleu:BAAANQAECggIDQABNQAECggIGAAWAGUQAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECn8jAAMXAAkKtBakMwAPAgAXAAkKjhWkMwAPAgAYAAcKihM3MgCwAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgoKNwAGAOohAA==.Blèu:BAABNQAECn8YAAIWAAgKZRD6HAC2AQAWAAgKZRD6HAC2AQAAAA==.',
Bo='Boggrog:BAAANQAECgQIBwAAAQ==.Bokan:BAAANQAECgQICAAAAA==.Boneappetit:BAAANQADCgYIBgABNQAECgkJKAAZANcTAA==.Borgasthe:BAAANQADCgEIAQAAAA==.Box:BAAANQAECgcICAAAAA==.',
Br='Braggs:BAAANQAECgQIAwAAAA==.Breathe:BAAANQAECgUIBQAAAA==.Brewballs:BAABNQAECn8ZAAIWAAcKAwpUKAAxAQAWAAcKAwpUKAAxAQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIHgAAAA==.Bucket:BAAANQAECgcIDwAAAA==.Bunnicula:BAABNQAECn8kAAQUAAoKXhXNBgA6AgAUAAkKpRXNBgA6AgAOAAMKfAckGgGTAAABAAEKbBN3cAA/AAAAAA==.',
['Bö']='Böömer:BAAANQAECgQICgAAAA==.',
Ca='Caelphia:BAAANQAECgUIDgAAAA==.Caimage:BAABNQAECn8XAAIGAAgKZxIkzwDoAQAGAAgKZxIkzwDoAQAAAA==.Cainnaszun:BAAANQAECgEIAgAAAA==.Cainnaszunn:BAAANQADCggIGwABNQAECgEIAgAFAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Catara:BAAANQAECgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFH8lAAQOAAgKgiA8BAA1AgAOAAYKrx08BAA1AgABAAIKJiaTAwDdAAAUAAIKkh0vAgBlAAA1AAQKfzAABAEACgrYIsABAGMDAAEACQq4I8ABAGMDAA4ACAq0JgkQAFIDABQAAgpFB80iAGYAAAAA.Caythuz:BAAANQAECgYICwABNQAFFAgIJQAOAIIgAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgQIBAAAAA==.Chakabad:BAAANQAECgQICQAAAA==.Chalgah:BAAANQAECgIIBgAAAA==.Charnyanya:BAAANQADCggICAABNQAECgcIDQAFAAAAAA==.Chenahala:BAAANQAECgQICQAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECn9AAAIYAAoKNh+sBADPAQAYAAoKNh+sBADPAQAAAA==.',
Ci='Cimerone:BAAANQABCgYICQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAABNQAECn8eAAMLAAcKUgpGLQBpAQALAAcKUgpGLQBpAQAaAAUKegJuXQCwAAAAAA==.Claw:BAAANQAECggIEAABNQAFFAYIDQAIAF4NAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgcIDgAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Conanascus:BAAANQADCgcIDgABNQAECgoKMQAbAFAPAA==.Confessorr:BAAANQADCgYIBQABNQAECgYIFQAOABgGAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAAANQAECgUIEgAAAA==.Crowe:BAAANQAECgMIBAAAAA==.',
Cy='Cynderr:BAABNQAECn8bAAIVAAgKABKEGADAAQAVAAgKABKEGADAAQAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQAECgQIBAAAAA==.Darkisis:BAAANQAECgYIDgAAAA==.Darknara:BAABNQAECn8nAAMQAAkKBR3GIACuAgAQAAkKBR3GIACuAgAIAAUKHRMPIwDbAAAAAA==.Darkterror:BAAANQAECgQIBAABNQAECgYIDgAFAAAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgMICAAAAA==.Dasubertakem:BAAANQADCgYIDQAAAA==.Dawni:BAABNQAECn8jAAQTAAoKwg9eDQDxAAATAAgKsg1eDQDxAAAVAAQK+REsCgDHAAAcAAEKiAQWJgAsAAAAAA==.',
Dd='Ddz:BAAANQADCgUIBQAAAA==.',
De='Deathjeff:BAABNQAECn8cAAIJAAoKsCJmBwBuAwAJAAoKsCJmBwBuAwAAAA==.Deathsgates:BAAANQAECgUIDQABNQAFFAQICQAbANQQAA==.Detala:BAAANQADCgYICQAAAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgUIDQAAAA==.Dinoll:BAAANQAECgQIBgAAAA==.Dirtwhistle:BAABNQAECn8qAAIdAAkKZSQnAgCaAwAdAAkKZSQnAgCaAwAAAA==.',
Dr='Dracont:BAAANQADCgUIBQABNQAECgEIAgAFAAAAAA==.Dragondh:BAACNQAFFH8JAAIXAAQK1Qd/BgDFAAAXAAQK1Qd/BgDFAAA1AAQKfyYAAhcACgpaGzElAHMCABcACgpaGzElAHMCAAAA.Dranlu:BAAANQADCgYICQAAAA==.Drazsi:BAAANQAECgUICwAAAA==.Drekkara:BAAANQADCgQIBAABNQAECgMIDAAFAAAAAA==.Drosi:BAABNQAECn8oAAIRAAcKehKLKgCAAQARAAcKehKLKgCAAQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
['Då']='Dåmmn:BAAANQAECgEIAQAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECgcIEAAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAABNQAECn8cAAMZAAcKwhIEHwDzAAAZAAcKwhIEHwDzAAAeAAMKdRCxWQChAAAAAA==.Electricfury:BAAANQAECgUIBQAAAA==.Elementalism:BAAANQADCgQIBAAAAA==.Ellebasi:BAAANQAECgQIBwAAAA==.Ellebazy:BAABNQAECn8dAAISAAcK/hNOKgCLAQASAAcK/hNOKgCLAQAAAA==.',
Em='Emmri:BAAANQAECgcIDgAAAA==.',
En='Enazen:BAABNQAECn8UAAIVAAYKThf5GwCMAQAVAAYKThf5GwCMAQAAAA==.Enlighthyn:BAABNQAECn8aAAINAAkK0R4oIADuAgANAAkK0R4oIADuAgABNQAFFAUIDAAHAO4dAA==.',
Er='Erlas:BAAANQAECgMIAwAAAA==.Erui:BAAANQAECgQICQAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCggIDQAAAA==.Etrexxig:BAAANQADCgcICwAAAA==.',
Ev='Evilrayne:BAABNQAECn86AAIGAAoKrRRoHwCTAQAGAAoKrRRoHwCTAQAAAA==.',
Fa='Fanfiction:BAABNQAECn8cAAMTAAoK2xFbGwASAgATAAoK2xFbGwASAgAVAAEKAAD+QQAmAAAAAA==.Fatherfingur:BAAANQADCgMIBAAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgcIEQAAAA==.Felmonger:BAAANQAECgQICQAAAA==.Feloak:BAABNQAECn8dAAIfAAcKKQu3BwD5AAAfAAcKKQu3BwD5AAAAAA==.Feredir:BAAANQAECgQIBwAAAA==.',
Fi='Fires:BAABNQAECn8iAAQGAAgKIh+XXADGAgAGAAgKwx6XXADGAgAgAAQK5x2bFwA+AQAhAAEKAABhDQA4AAAAAA==.Fistandilius:BAABNQAECn8XAAIOAAcKLw5XnwCYAQAOAAcKLw5XnwCYAQAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECn8rAAMQAAkKLiKZEQAgAwAQAAkKLiKZEQAgAwAJAAEKAADRngBTAAAAAA==.',
Fu='Furryfury:BAABNQAECn83AAMWAAoKBxowDgCgAgAWAAoKBxowDgCgAgAMAAEKAADnawAyAAAAAA==.Fusrodah:BAABNQAECn8hAAMTAAgKxxccGQAuAgATAAgKxxccGQAuAgAVAAEKAACsOQBBAAAAAA==.Fuzzyewok:BAABNQAECn8oAAINAAcKkx4WCQAyAgANAAcKkx4WCQAyAgAAAA==.',
Ga='Gabaghoul:BAABNQAECn8tAAIQAAoKqBgjMABRAgAQAAoKqBgjMABRAgAAAA==.Gameshark:BAABNQAECn8dAAINAAcKZiV3AwDHAgANAAcKZiV3AwDHAgAAAA==.Gawdzirra:BAAANQAECgcIEAAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAFFAEIAQAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.Ghulrokk:BAAANQAECgQIBAAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQAECgMIAwAAAA==.',
Go='Gohibasi:BAAANQAECgQIBwAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAABNQAECn8YAAIHAAoKVxI4TwA3AgAHAAoKVxI4TwA3AgAAAA==.',
Gr='Graceosilver:BAAANQAECgUIDAAAAA==.Gregnor:BAABNQAECn8oAAUCAAcK4xJWBgBPAQACAAcK4xJWBgBPAQAZAAYKVAYzbAAaAQAiAAQKTgjzRQCbAAAeAAQKmwOaZQBvAAAAAA==.Gremöry:BAABNQAECn8aAAMPAAcKsBPKmgBiAQAPAAYKwRHKmgBiAQAjAAcKVhEcSQDQAAAAAA==.Grippysock:BAAANQAECgIIAgAAAA==.Grover:BAABNQAECn8jAAIRAAkKWBR4ggAjAgARAAkKWBR4ggAjAgAAAA==.Grumpybunbun:BAABNQAECn8lAAIHAAoKKRKxUwAoAgAHAAoKKRKxUwAoAgAAAA==.Grüm:BAAANQAECgQIBwAAAA==.',
Gu='Guldangraham:BAAANQAECggIAgABNQAECggIDwAFAAAAAA==.Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAABNQAECn8jAAILAAkKaxhSCgAlAgALAAkKaxhSCgAlAgAAAA==.',
['Gô']='Gôrbag:BAAANQADCgUIBQAAAA==.',
Ha='Haarl:BAAANQADCgcIBwAAAA==.Hairypotter:BAAANQADCggIFQABNQAECgQICQAFAAAAAA==.Halazzi:BAAANQAECgEIAgAAAA==.Haldar:BAAANQAECgYIDAAAAA==.Hallie:BAAANQAECgUIDAAAAA==.Harlu:BAABNQAECn8UAAIPAAYKdgVduQAfAQAPAAYKdgVduQAfAQAAAA==.Hartbroke:BAABNQAECn8XAAIRAAYKTRuyoQDeAQARAAYKTRuyoQDeAQAAAA==.Haunter:BAAANQAECgQIDAABNQAECgkJHQAeAN8dAA==.Hayeon:BAAANQAECgEIAQABNQAECgMIAgAFAAAAAA==.',
He='Helbourne:BAABNQAECn8XAAIXAAcKdBYPMAAnAgAXAAcKdBYPMAAnAgAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECggICwAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgUIGQAkAJcUAA==.Hunsx:BAAANQAECgYICQAAAA==.Huntingpups:BAAANQADCggICAAAAA==.',
Hw='Hwanwok:BAABNQAECn8gAAIMAAgK7xPrKwC8AQAMAAgK7xPrKwC8AQAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ia='Iamwarlock:BAAANQADCgYICwAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQAECgUICAAAAA==.',
Il='Ilotei:BAAANQADCgcIBwAAAA==.',
Im='Imadragon:BAABNQAECn8mAAIVAAoKCgw6GADFAQAVAAoKCgw6GADFAQAAAA==.Imbac:BAAANQAECgEIAgAAAA==.Imdeadguy:BAABNQAECn8mAAIdAAkKISDzBgDxAgAdAAkKISDzBgDxAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCggIHgAAAA==.Ironhelmhtr:BAAANQAECgQIBQAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jaayk:BAAANQAECggIEgAAAA==.Jace:BAAANQAECgIIAgAAAA==.Jazlee:BAABNQAECn8UAAIdAAYK0B1ZFQDSAQAdAAYK0B1ZFQDSAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgUICAAFAAAAAA==.Jefflock:BAAANQADCgEIAQABNQAECgcIFQALAF8WAA==.Jezmund:BAABNQAECn8ZAAIeAAUK+RhZNgBpAQAeAAUK+RhZNgBpAQAAAA==.',
Ji='Jinathy:BAABNQAECn8lAAIRAAoKqA/vWwANAQARAAoKqA/vWwANAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAAANQAECgcIEAABNQAECgoKHwAlAK4LAA==.',
Ju='Juaranir:BAABNQAECn8kAAIiAAgKxRPkCgBOAQAiAAgKxRPkCgBOAQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQAECgQIBwABNQAECgUICAAFAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàß:BAAANQAECgYIEQAAAA==.',
['Já']='Jáß:BAABNQAECn8ZAAINAAkK2R3NGgALAwANAAkK2R3NGgALAwAAAA==.',
['Jä']='Jäb:BAAANQAECgcICgAAAA==.',
Ka='Kagegari:BAAANQADCgUIBQABNQAFFAIIBgALAJsdAA==.Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAABNQAECn8yAAIJAAoK6w16GgBBAQAJAAoK6w16GgBBAQAAAA==.Kalenia:BAABNQAECn85AAIjAAoKdx9LBQCLAgAjAAoKdx9LBQCLAgAAAA==.Kalvayre:BAAANQAECgQICQAAAA==.Kanzoorb:BAABNQAECn8mAAMGAAoKzBumVADXAgAGAAoKzBumVADXAgAgAAEKIBfxFwBFAAAAAA==.Kareshka:BAABNQAFFH8HAAMgAAUKFQ20BADIAAAGAAMKAwcXOwDYAAAgAAMKVRG0BADIAAAAAA==.Karinea:BAEBNQAECn8UAAImAAcK8gWyIQDPAAAmAAcK8gWyIQDPAAAAAA==.Karpana:BAEBNQAECn8sAAMSAAgK/RWwLwBhAQARAAgKqRFm1gBvAQASAAUKZxywLwBhAQAAAA==.Karreena:BAAANQADCgYIBgAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAAANQAECgUIDgAAAA==.Kashira:BAAANQADCggIEgABNQAECgUIDgAFAAAAAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kaythewitch:BAAANQAECgcIBwAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAAANQAECgQIDAAAAA==.',
Ke='Keekat:BAAANQADCggIGAAAAA==.Kevinbeacon:BAEANQAECgYIEgAAAA==.',
Kh='Kharnij:BAAANQAECgQICAAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAABNQAECn8mAAQOAAcKrRTeUQDgAAAOAAYKKxbeUQDgAAAUAAIKUA0NCgCBAAABAAEKEBPtFAA+AAAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQAFAAAAAA==.',
Ki='Kiamei:BAAANQAECgEIAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kissandia:BAAANQADCgcIBwAAAA==.Kittykitty:BAABNQAECn8nAAMjAAkK0h94JQDPAgAjAAkK0h94JQDPAgAPAAUKghZ9qABDAQAAAA==.',
Ko='Kolzane:BAECNQAFFH8RAAILAAcKuCOfAAC5AgALAAcKuCOfAAC5AgA1AAQKfyQAAgsACgqLJUMMAHsDAAsACgqLJUMMAHsDAAAA.',
Kr='Krezz:BAABNQAECn8XAAIdAAcKExplDwA1AgAdAAcKExplDwA1AgAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFH8MAAILAAUKYQ+WDgBtAQALAAUKYQ+WDgBtAQA1AAQKfx8AAgsACgpZGqQwANoCAAsACgpZGqQwANoCAAAA.',
Ky='Kynlyn:BAAANQADCgQICAAAAA==.Kyth:BAABNQAECn8nAAMSAAgKbRtKCAB3AQASAAgKbRtKCAB3AQARAAEKAAAVrAExAAAAAA==.Kythlock:BAAANQADCgYIBQABNQAECggIJwASAG0bAA==.Kythrax:BAAANQADCgUIAwABNQAECggIJwASAG0bAA==.Kythtok:BAAANQADCgYICAABNQAECggIJwASAG0bAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAABNQAECn8ZAAIQAAgKPx2mJwCCAgAQAAgKPx2mJwCCAgAAAA==.Laylanduin:BAAANQADCgEIAQABNQAECgoKHAAJALAiAA==.',
Le='Leadfarmer:BAAANQAECggIBAAAAA==.Lenash:BAAANQAECgIIAgABNQABCgIIBAAFAAAAAA==.',
Li='Lichlighter:BAAANQADCgEIAQAAAA==.Lifebloomer:BAAANQAECgEIAQABNQAFFAcIHgAQAB0iAA==.Lightguard:BAABNQAECn8iAAIRAAkKKBZpDwABAgARAAkKKBZpDwABAgAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgUIEgAAAA==.Littlehell:BAAANQAECggIEgAAAA==.',
Lo='Lothrik:BAAANQAECgYICwAAAA==.',
Lu='Lucaafer:BAAANQADCgYIFwABNQAFFAEIAQAFAAAAAA==.Luda:BAAANQAECgYIEgABNQAECgcIEAAFAAAAAA==.Ludaa:BAAANQAECgcIDgABNQAECgcIEAAFAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgcIEAAFAAAAAA==.Lunamoonclaw:BAABNQAECn8UAAIaAAcKdAZ2QQBJAQAaAAcKdAZ2QQBJAQAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAAANQAECgUICQAAAA==.Lyzoldas:BAABNQAECn8bAAIRAAkK3hJplgD3AQARAAkK3hJplgD3AQAAAA==.',
['Lá']='Lárry:BAAANQADCgUIBwAAAA==.',
['Lö']='Löwryder:BAAANQAECgQIDgAAAA==.',
Ma='Madness:BAAANQADCgYIBwABNQAECggIIgAPAP4MAA==.Mae:BAABNQAECn8WAAQTAAgKORp6AgAVAgATAAgKORp6AgAVAgAVAAEKtx+aOABKAAAcAAEKEQFVKQAVAAABNQABCgIIAgAFAAAAAA==.Maemura:BAAANQAECgQIBwAAAA==.Magdalaiina:BAABNQAECn8bAAINAAYKhSEXTQA1AgANAAYKhSEXTQA1AgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magusman:BAAANQAECgcICAABNQAECgkJKwAQAC4iAA==.Magîkarp:BAABNQAECn8YAAMWAAgKSxk4GwDOAQAWAAgKSxk4GwDOAQAMAAMKnRDSXgBlAAAAAA==.Malchromatus:BAABNQAECn8nAAMTAAkKZAprJQCTAQATAAkKZAprJQCTAQAVAAcKWwaXIQBCAQAAAA==.Marcosio:BAAANQAECgMIBwAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAABNQAECn8XAAIZAAkKaQu9SgC7AQAZAAkKaQu9SgC7AQAAAA==.Mavik:BAAANQAECggIAgAAAA==.Maylater:BAAANQAECgMIAwABNQAECgkJGgAMAIARAA==.',
Me='Mearkman:BAAANQAECgQIEAAAAA==.Meatyfajita:BAABNQAECn8eAAINAAgKAiaADABkAwANAAgKAiaADABkAwAAAA==.Megumim:BAAANQADCgQIBAAAAA==.Meinfurion:BAABNQAECn8ZAAMZAAgKKxMcSADKAQAZAAcKSBUcSADKAQAeAAcKVBIzLwChAQAAAA==.Meinstrom:BAAANQADCggICAABNQAECggIGQAZACsTAA==.Meladie:BAAANQAECgEIAQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAABNQAECn8yAAQJAAoKWh4RBwDoAQAIAAgKJyL8HgDRAgAJAAoKNRMRBwDoAQAQAAEKAADluwBQAAAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECgoKMgAJAFoeAA==.Merit:BAAANQADCggIEAABNQAECgkJIwAXALQWAA==.Merlinthos:BAABNQAECn8aAAMGAAgKMAQuFgFnAQAGAAgKMAQuFgFnAQAgAAIKuwJBFgBSAAABNQAECgoKMQAbAFAPAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAABNQAECn8oAAMgAAcKbiESAgDOAQAGAAcKOx6WiABtAgAgAAYKtCASAgDOAQAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAAFAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECn8gAAIkAAkKSxnKBwB0AgAkAAkKSxnKBwB0AgAAAA==.Mingyue:BAAANQAECgUIBQABNQAECgkJKAAZANcTAA==.Mirajåne:BAACNQAFFH8HAAIEAAMK4RAPDgDzAAAEAAMK4RAPDgDzAAA1AAQKfzoABAQACgqbHBMPAAEDAAQACgqbHBMPAAEDAAcABQplF4ymACEBACcAAQq6Aq0tACkAAAAA.Mishaweha:BAABNQAECn8YAAIjAAgKoAvHjQBmAQAjAAgKoAvHjQBmAQAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQADCggIEQAAAA==.',
Mo='Modar:BAABNQAECn8lAAMjAAoKzRURRwBFAgAjAAoKzRURRwBFAgAPAAMKsgQQ5gDLAAAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQAECgQIBQAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.Navatath:BAAANQAECgMIBgABNQAFFAcIJgAGAL8kAA==.',
Ne='Neiidra:BAAANQAECgUIBgAAAA==.Nepheleah:BAACNQAFFH8JAAIRAAQKuRhVBgD5AAARAAQKuRhVBgD5AAA1AAQKfy4AAhEACgoTIqIPAIwDABEACgoTIqIPAIwDAAAA.Nesca:BAABNQAECn8bAAIjAAcKKQtvSADSAAAjAAcKKQtvSADSAAAAAA==.Nesmoth:BAAANQAECgUIDgAAAA==.Ness:BAABNQAECn8dAAMWAAcKHw5CDAAQAQAWAAcKHw5CDAAQAQAmAAQKSAzPIQDNAAAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQADCggIDQAAAA==.Niiborracho:BAABNQAECn8kAAMMAAgKJw6pEQAgAQAMAAgKJw6pEQAgAQAWAAUKNBHxLQD8AAAAAA==.Niiko:BAAANQAECgQIEgAAAA==.',
No='No:BAAANQADCgUJBQABNQAECgoKLAADAHEhAA==.Nobullsheep:BAAANQABCggIBwAAAA==.Nommy:BAAANQAECgcIDwABNQAECggILgALADUbAA==.Norntrox:BAAANQAECgYIEAAAAA==.Nothannah:BAABNQAECn8jAAIeAAkKXRCVJQD3AQAeAAkKXRCVJQD3AQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECgkJIwAXALQWAA==.',
Og='Ogreatsxtra:BAAANQAECgQICwAAAA==.',
Ol='Ol:BAAANQAECgcICwAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECggICgABNQAECgkJHQAeAN8dAA==.',
Or='Orangecrush:BAAANQAECgUIAwAAAA==.Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgcIDgAAAA==.',
Oz='Ozhawk:BAAANQAECgUIBwAAAA==.',
Pa='Padreburrito:BAEANQADCgYICwABNQAFFAcIDQAeABcfAA==.Pakno:BAAANQAECgUIBQAAAA==.Pamely:BAABNQAECn9AAAIRAAoKmh+yGgBZAwARAAoKmh+yGgBZAwAAAA==.',
Pe='Perices:BAAANQADCgYIBgAAAA==.',
Ph='Pharmit:BAABNQAECn8rAAMUAAcK+iVMAAB1AgAUAAcK+iVMAAB1AgAOAAEKXSFhMAFbAAAAAA==.Phiarce:BAABNQAECn8fAAIEAAoKxxKDBQCkAQAEAAoKxxKDBQCkAQAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgUIBwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAABNQAECn8cAAIGAAgKwBM1wwD+AQAGAAgKwBM1wwD+AQAAAA==.Pyramys:BAAANQABCgQIAwABNQAECggIIAAKAJodAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgQICQAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECgoKLwAQAH0lAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.Ralsei:BAAANQAECgEIAQAAAA==.Ramasey:BAAANQAECgEIAQAAAA==.',
Re='Reach:BAAANQADCgYICgABNQAECgoKLQAPADkRAA==.Readdyy:BAAANQAECgcIBwAAAA==.Real:BAABNQAECn8fAAIGAAgKvhvJfQCDAgAGAAgKvhvJfQCDAgABNQABCgIIAgAFAAAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQAECgUIBwAAAA==.Redangus:BAAANQADCgIIAgABNQAECgYIBwAFAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAYIGQAZABQcAA==.Revoke:BAABNQAECn8dAAIRAAgKAwrnZgD4AAARAAgKAwrnZgD4AAAAAA==.',
Ro='Rocknrolln:BAAANQADCgYIDAAAAA==.Rokubora:BAABNQAECn8iAAMPAAgKnBSzUgAuAgAPAAgKnBSzUgAuAgAjAAYKFAvZqwAZAQAAAA==.Rongyi:BAAANQAECgEIAQABNQAECgkJKAAZANcTAA==.Roronoa:BAAANQADCgYICwAAAA==.Roßyn:BAABNQAECn8lAAMEAAoKJxSHJwDvAQAEAAgKbhWHJwDvAQAHAAYKew2UOwAWAQAAAA==.',
Ru='Rubah:BAABNQAECn8ZAAINAAgKbhCVdAC6AQANAAgKbhCVdAC6AQAAAA==.Rundail:BAAANQADCgQIBAAAAA==.Ruroni:BAABNQAECn8VAAILAAgK1A1iyQBvAQALAAgK1A1iyQBvAQAAAA==.',
Ry='Ryniel:BAAANQAECgIIAgAAAA==.',
['Ré']='Rédundant:BAAANQAECgcIDgABNQAECgoKLQAPADkRAA==.',
['Rì']='Rìzz:BAABNQAECn8lAAIPAAgKnR0iNQCjAgAPAAgKnR0iNQCjAgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEJAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgUICwAFAAAAAA==.Sannaggi:BAAANQAECgYIDgAAAA==.Sarahnox:BAABNQAECn8gAAMeAAkKIhlQGwBeAgAeAAkKIhlQGwBeAgAZAAIKRQukUwAyAAAAAA==.Saramoon:BAABNQAECn8XAAIKAAcKawZxKwBnAQAKAAcKawZxKwBnAQAAAA==.Sarayana:BAAANQABCgMIBAAAAA==.Sargent:BAAANQADCggIGAAAAA==.Saryaa:BAAANQAECgcICwAAAA==.Sashchi:BAABNQAECn8hAAIMAAcKFRLoEQAeAQAMAAcKFRLoEQAeAQAAAA==.Sassenach:BAAANQAECgQIBgAAAA==.Saudelber:BAAANQAECgUIBgAAAA==.',
Sc='Schanks:BAABNQAECn8WAAIbAAgKkhxNFwDCAgAbAAgKkhxNFwDCAgAAAA==.Scoliosisstu:BAAANQADCggICAAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQAECgEIAQABNQAECgkJIwAeAF0QAA==.Sehmet:BAAANQAECgQIDgAAAA==.Sekaï:BAAANQADCgEIAQAAAA==.Seliria:BAABNQAECn8oAAIRAAcKRROSKgB/AQARAAcKRROSKgB/AQAAAA==.Seoulmate:BAABNQAECn8oAAIZAAkK1xO/NgA2AgAZAAkK1xO/NgA2AgAAAA==.Sera:BAABNQAECn8YAAIRAAgKkhRligARAgARAAgKkhRligARAgAAAA==.Severûs:BAAANQAECgEIAQAAAA==.',
Sh='Shadoezz:BAAANQADCgQIBAAAAA==.Shadowk:BAAANQABCgIIAgAAAA==.Shamsicle:BAAANQADCgMIAwAAAA==.Shaye:BAAANQAECgQIDQAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECggIDwAFAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shiryo:BAAANQAECgQIBAAAAA==.Shotfoot:BAABNQAECn8sAAILAAoK4ReqOwC3AgALAAoK4ReqOwC3AgAAAA==.Shwang:BAABNQAECn8WAAILAAgKIRvINQBQAQALAAgKIRvINQBQAQAAAA==.',
Si='Sihåya:BAAANQAECgcIEAAAAA==.Silbergrad:BAAANQADCggIHAAAAA==.Silentio:BAABNQAECn8xAAIbAAoKUA80BwCnAQAbAAoKUA80BwCnAQAAAA==.Silihunt:BAABNQAECn8wAAMYAAkK5xXuDwAzAQAXAAgKrxKpOgDgAQAYAAgKihbuDwAzAQAAAA==.Sinofwrath:BAAANQAECgcIDQAAAA==.Sinsidious:BAAANQAECgYICwAAAA==.Siwin:BAECNQAFFH8NAAIeAAcKFx/AAgAwAgAeAAcKFx/AAgAwAgA1AAQKfyYAAx4ACgpDJU0DAJQDAB4ACgpDJU0DAJQDABkAAgoAAJabAGwAAAAA.',
Sk='Skribb:BAABNQAECn8nAAINAAgKdiJwDQD0AQANAAgKdiJwDQD0AQAAAA==.',
Sl='Slapchóp:BAABNQAECn8gAAIPAAcKmR1YBwDyAQAPAAcKmR1YBwDyAQAAAA==.',
Sm='Smiley:BAACNQAFFH8WAAIHAAcK3hUFAwDoAQAHAAcK3hUFAwDoAQA1AAQKfyUAAgcACgqtGBdDAF8CAAcACgqtGBdDAF8CAAE1AAUUBwoWAAcA3hUA.Smoketron:BAAANQAECgQIBAABNQAECgcICQAFAAAAAA==.Smoko:BAAANQAECgQIBgAAAA==.',
Sn='Sneakyboi:BAAANQAECggIDwAAAA==.Snorlax:BAABNQAECn8dAAQeAAkK3x0dFwCIAgAeAAkK3x0dFwCIAgAiAAMKFRa0SACLAAAZAAIKYBUuogBYAAAAAA==.Snowsu:BAACNQAFFH8aAAMOAAcKDyM+AwBRAgAOAAYKwyI+AwBRAgABAAIKJiEkBgC/AAA1AAQKfzQABA4ACgqpJmIBAOgDAA4ACQqdJmIBAOgDAAEABwqUHdsKAEkCABQAAQqHJrAKAHUAAAAA.Snowxstorm:BAABNQAECn8jAAIQAAcKexrqCQCgAQAQAAcKexrqCQCgAQAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAABNQAECn8VAAILAAcKXxaIrgCnAQALAAcKXxaIrgCnAQAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAABNQAECn8lAAIIAAcK8g1dDgBsAQAIAAcK8g1dDgBsAQAAAA==.',
Sp='Splashzone:BAABNQAECn8cAAIjAAcK6gkenwA5AQAjAAcK6gkenwA5AQAAAA==.',
St='Staqua:BAAANQAECgQIDAAAAA==.Stateomatter:BAABNQAECn8YAAILAAgKYQp9lwDZAQALAAgKYQp9lwDZAQAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECgkJKAAZANcTAA==.Summdari:BAABNQAECn8hAAIfAAgKzRXyCwAMAgAfAAgKzRXyCwAMAgAAAA==.Summrot:BAABNQAECn8aAAMOAAkKVQ61ZAC5AAAOAAcKxA21ZAC5AAABAAMKjQ26RgCsAAAAAA==.Sunfrostt:BAAANQAECgUICgAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgQIDAAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgYIDAAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAABNQAECn8eAAMjAAoKjhZ2FwCbAQAjAAoKjhZ2FwCbAQAoAAIKaggwMABtAAAAAA==.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgIIBAAAAA==.Tekeeladin:BAAANQAECgQIAwABNQAFFAIIBgALAJsdAA==.Tekeelà:BAABNQAECn8lAAILAAgKACA3DgAAAgALAAgKACA3DgAAAgABNQAFFAIIBgALAJsdAA==.Tekelemental:BAABNQAECn8bAAIPAAcKfQ4IKwARAQAPAAcKfQ4IKwARAQAAAA==.Tempestra:BAAANQAECgYIDAAAAA==.Tenebria:BAABNQAECn81AAIlAAoKnB6VAQBNAwAlAAoKnB6VAQBNAwAAAA==.Terrorhungry:BAAANQAECgUIDQAAAA==.',
Th='Thalstrasza:BAABNQAECn8hAAIOAAgKQQyrowCOAQAOAAgKQQyrowCOAQAAAA==.The:BAAANQAECgUIDgAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAABNQAECn8dAAMGAAgK7xXO3QDMAQAGAAcKFBTO3QDMAQAgAAIKzxu9LwCCAAAAAA==.Theodiseus:BAAANQADCgUIBQAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tibalt:BAAANQAECgIIAgAAAA==.Tietus:BAAANQAECgUIBgAAAA==.',
Tl='Tlanimass:BAABNQAECn8UAAIdAAYKABOOHwBUAQAdAAYKABOOHwBUAQAAAA==.',
To='Tolac:BAAANQADCgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAcICwAOAIQRAA==.Treyna:BAAANQADCgMIAwAAAA==.',
Ts='Tsu:BAAANQAECgcIEgAAAA==.Tsyubaki:BAAANQAECgQICwAAAA==.',
Tu='Tulisse:BAAANQAECgEIAQAAAA==.',
Tw='Twerkngherkn:BAAANQAECgcIDAAAAA==.',
Ty='Tybalt:BAABNQAECn8uAAIoAAoKPyK8AgB7AwAoAAoKPyK8AgB7AwAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECggIEQAAAA==.',
Ul='Uldric:BAABNQAECn8XAAIJAAcKBwVbYwAWAQAJAAcKBwVbYwAWAQAAAA==.',
Un='Undeaddude:BAAANQAECgUICAAAAA==.Unslayable:BAAANQAECgQICgAAAA==.',
Uz='Uzzy:BAAANQAECgQICQAAAA==.',
Va='Valandir:BAABNQAECn8ZAAMRAAcK7Q2QxgCPAQARAAcK7Q2QxgCPAQASAAMKOgU3XABqAAAAAA==.Valyst:BAAANQAECgEIAgAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFH8XAAIeAAYKBR6NAQDDAQAeAAYKBR6NAQDDAQA1AAQKfyQAAx4ACgqZFE8cAFMCAB4ACgqZFE8cAFMCABkABgpsBaF7AN0AAAAA.Verrenth:BAAANQAECggIBgABNQAECggIDwAFAAAAAA==.',
Vi='Viduus:BAAANQAECgMIBgAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECggIGgAHAOIYAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgYIEwAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQAFAAAAAA==.',
Wf='Wfreemen:BAAANQADCgQIBAAAAA==.',
Wh='Who:BAAANQAECgcICwABNQAFFAUICwAHAAMGAA==.',
Wi='Wickedholi:BAAANQAECgcIBwABNQAFFAcICwAOAIQRAA==.Wickedsmaht:BAACNQAFFH8LAAMOAAcKhBEvGAAzAQAOAAUKUREvGAAzAQABAAIK0BGNDgCZAAA1AAQKfzgABA4ACgopIesdAA0DAA4ACQpoIOsdAA0DAAEAAwrcIT0tABgBABQAAwoQITcHAL8AAAAA.Widowghast:BAABNQAECn8fAAIGAAgKXBR4vAALAgAGAAgKXBR4vAALAgAAAA==.Willowísp:BAABNQAECn8pAAImAAoKIBzHBgDZAgAmAAoKIBzHBgDZAgAAAA==.Witerally:BAAANQAECgQICgAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEBNQAECn8XAAMLAAcKmhHzsQCgAQALAAcKmhHzsQCgAQAaAAEKbAZ3kgAuAAAAAA==.',
Wy='Wynters:BAAANQAECgQIBAAAAA==.',
Xa='Xalthea:BAABNQAECn8yAAQYAAoKIA6jBgClAQAYAAoKIA6jBgClAQAfAAEKwQj9NgAhAAAXAAcKGgCuowAUAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAFFAQICQAbANQQAA==.Xanlock:BAAANQADCgUIBwABNQAECgkJJAAiAP8WAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECgkJKAAZANcTAA==.',
Xp='Xpddevour:BAABNQAECn8zAAIXAAoKwxQwBAAtAgAXAAoKwxQwBAAtAgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAACNQAFFH8HAAIRAAMKuwloCQDSAAARAAMKuwloCQDSAAA1AAQKfzIAAhEACgo7HkQzAP8CABEACgo7HkQzAP8CAAAA.',
Xu='Xuxo:BAAANQADCgYIBwAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.Yawning:BAAANQADCgcIBwABNQAECgoKLQAPADkRAA==.',
Ye='Yegarmiester:BAAANQAECgcIDAAAAA==.Yenti:BAAANQAECgUIDQAAAA==.',
Yu='Yuexi:BAAANQAECgIIAgABNQAECgkJKAAZANcTAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAABNQAECn8ZAAIkAAUKlxQMCwDNAAAkAAUKlxQMCwDNAAAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQAECgcIBgABNQAECgkJHQAeAN8dAA==.Zatapa:BAAANQAECgUIBQAAAA==.',
Ze='Zendàya:BAAANQADCgEIAQAAAA==.Zerality:BAAANQAECgYIDgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAABNQAECn8nAAIYAAkKeCQdAQC9AgAYAAkKeCQdAQC9AgAAAA==.Zinovia:BAAANQAECgQIBAAAAA==.',
Zo='Zoltan:BAAANQADCggIGgAAAA==.Zookee:BAABNQAECn8lAAIWAAcKXgt1CQBAAQAWAAcKXgt1CQBAAQAAAA==.',
Zu='Zulizek:BAABNQAECn8jAAIjAAkKtwp4MQAdAQAjAAkKtwp4MQAdAQAAAA==.',
Zy='Zynister:BAABNQAECn8lAAMJAAoKdR26AwBBAgAJAAoKdR26AwBBAgAQAAUKzRFOgQD2AAAAAA==.',
['Ûr']='Ûrta:BAAANQADCgEIAQAAAA==.',
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
