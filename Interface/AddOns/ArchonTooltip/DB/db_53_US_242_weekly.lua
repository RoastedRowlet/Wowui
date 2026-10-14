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

local lookup = {'Unknown-Unknown','Druid-Feral','Warrior-Arms','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Monk-Windwalker','Hunter-BeastMastery','Paladin-Holy','DeathKnight-Blood','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Druid-Balance','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Druid-Restoration','Priest-Holy','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Hunter-Survival','Priest-Discipline','Shaman-Enhancement','Monk-Brewmaster',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aahnna:BAAANQADCggICAABNQAECgcIEQABAAAAAA==.',
Ab='Ababear:BAAANQAECgQIBwABNQAFFAMIBQACAKcdAA==.',
Ad='Adeki:BAAANQADCgYIBgAAAA==.Ademai:BAAANQABCgYICgAAAA==.',
Ag='Agakk:BAAANQADCggICAAAAA==.Agentbundles:BAAANQADCgUIBwAAAA==.',
Ah='Ahnna:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.',
Al='Alarrius:BAABNQAECn8rAAIDAAgKnBKKhQAKAgADAAgKnBKKhQAKAgAAAA==.Albedö:BAAANQADCgIIAgABNQAFFAMIBwAEAOEQAA==.Algo:BAAANQAECgIIAgAAAA==.Algrubeley:BAAANQABCgUIBQABNQAECgQIEAABAAAAAA==.Alithirae:BAAANQADCgYICgAAAA==.Allionys:BAAANQAECgYIEAAAAA==.Aloris:BAAANQAECgYIEwAAAA==.',
Am='Amanises:BAABNQAECn8iAAMFAAcKriBhKACWAgAFAAcKriBhKACWAgAGAAIKJgv6lABkAAABNQAECgkJHQAHAE4UAA==.Amilara:BAAANQAECgIIAwAAAA==.',
An='Anakota:BAAANQABCgEIAQAAAA==.Ananaya:BAAANQAECgMICQABNQAECgQIBwABAAAAAA==.Anania:BAAANQAECgQIBwAAAA==.Andinestiri:BAAANQAECgcIEgAAAA==.Andolastrasz:BAAANQAECgQICAAAAA==.Angelic:BAAANQAECgYIDQAAAA==.',
Ao='Ao:BAABNQAECn8pAAIIAAgKLSBDDwDsAgAIAAgKLSBDDwDsAgAAAA==.',
Ap='Apotic:BAABNQAECn8hAAIGAAcKOQOHagDrAAAGAAcKOQOHagDrAAAAAA==.Apuntar:BAAANQADCggIDgAAAA==.',
Aq='Aquamaree:BAAANQAECgEIAQAAAA==.Aquilla:BAACNQAFFH8LAAIJAAYK4QerCAC6AQAJAAYK4QerCAC6AQA1AAQKfyUAAgkACQpsHwA+AK4CAAkACQpsHwA+AK4CAAAA.',
Ar='Archenea:BAAANQAECgUIBgAAAA==.Archenore:BAAANQADCggIEAAAAA==.Areeza:BAAANQABCgIIAgAAAA==.Argord:BAABNQAECn8dAAIKAAcKuwaFogA8AQAKAAcKuwaFogA8AQAAAA==.Arhianrod:BAAANQADCggICgAAAA==.Ariisa:BAAANQAECgIIAgAAAA==.Around:BAAANQAECgYIEAABNQAECgcIDQABAAAAAA==.Artty:BAEANQAECgQIBAABNQAECgkJIgALAAImAA==.',
As='Askip:BAAANQADCgQICgAAAA==.Astrud:BAAANQAECgMICQAAAA==.Asukka:BAABNQAECn8XAAMMAAgKUxYikQD9AQAMAAgKqxQikQD9AQANAAQKWBU0RADdAAAAAA==.Asëya:BAAANQADCggIDwAAAA==.',
At='Atomique:BAACNQAFFH8ZAAIOAAUKLAvCCwBdAQAOAAUKLAvCCwBdAQA1AAQKfzEAAg4ACQpgICEFAFkDAA4ACQpgICEFAFkDAAAA.Attenborough:BAAANQADCgYIBgAAAA==.',
Au='Audiamer:BAAANQADCgUIBQABNQAECggIHgAPAM0HAA==.Augustine:BAAANQABCgIIAgAAAA==.',
Av='Avesa:BAAANQADCgcILwAAAA==.Avoidant:BAAANQADCggIEgAAAA==.',
Ay='Ayyahuasca:BAAANQABCgIIAgABNQAECgUIDwABAAAAAA==.',
Az='Azazell:BAAANQADCggIEQAAAA==.Azenea:BAAANQAECgcIEQAAAA==.',
Ba='Baculum:BAAANQAECgUIEgAAAA==.Badmoonrisin:BAAANQADCgYJCQAAAA==.Baieghzieghl:BAAANQADCgcIDgAAAA==.Bandolero:BAAANQAECgUIBQAAAA==.',
Be='Beangles:BAAANQADCggICAAAAA==.Beckyy:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Beefstewed:BAAANQADCggIDwAAAA==.Bekkÿ:BAAANQADCgUICQABNQAECgQIBQABAAAAAA==.Bellaboop:BAAANQADCgYIBgAAAA==.Bellapearl:BAAANQAECgcIEQAAAA==.Ben:BAAANQAECggICQAAAQ==.',
Bi='Bigbutter:BAAANQAECgMIBwAAAA==.Bittybow:BAAANQADCgQIBAAAAA==.Bittydrood:BAAANQAECgMIBAAAAA==.Bittylexis:BAAANQAECgUIEwAAAA==.',
Bl='Blackei:BAAANQADCgEIAQAAAA==.Blaiddgwyn:BAAANQADCgQIBQAAAA==.Blarcedeliu:BAAANQADCggICwABNQAECgYIEwABAAAAAA==.Bleu:BAAANQAECgcIBwABNQAECggIGAAQAGUQAA==.Blueaxle:BAAANQADCgEIAQAAAA==.Blur:BAABNQAECn8fAAMRAAgKjxb5MgAPAgARAAgKOBX5MgAPAgASAAcKihOjMQCwAQAAAA==.Bluzzy:BAAANQADCgIIAgABNQAECgkKLQATAPAgAA==.Blèu:BAABNQAECn8YAAIQAAgKZRC4HAC2AQAQAAgKZRC4HAC2AQAAAA==.',
Bo='Boggrog:BAAANQAECgQIBwAAAQ==.Bokan:BAAANQAECgQIBgAAAA==.Boneappetit:BAAANQADCgYIBgABNQAECggIJQAPADoVAA==.Box:BAAANQAECgcIBwAAAA==.',
Br='Braggs:BAAANQAECgEIAQAAAA==.Breathe:BAAANQAECgQIBAAAAA==.Brewballs:BAABNQAECn8ZAAIQAAcKAwraJwAxAQAQAAcKAwraJwAxAQAAAA==.Brewjitzu:BAAANQADCgQIBAAAAA==.',
Bu='Bubbletea:BAAANQADCggIHgAAAA==.Bucket:BAAANQAECgUIDQAAAA==.Bunnicula:BAABNQAECn8hAAQUAAkK7BW6BgA6AgAUAAgKVha6BgA6AgAVAAMKfAexFgGTAAAWAAEKbBPibwA/AAAAAA==.',
['Bö']='Böömer:BAAANQAECgMIBgAAAA==.',
Ca='Caelphia:BAAANQAECgUIDgAAAA==.Caimage:BAAANQAECgcIEwAAAA==.Cainnaszun:BAAANQAECgEIAQAAAA==.Cainnaszunn:BAAANQADCggIGwABNQAECgEIAQABAAAAAA==.Calistini:BAAANQADCgYICgAAAA==.Cameron:BAAANQADCgQIBAAAAA==.Catara:BAAANQAECgQIBAAAAA==.Cattform:BAAANQADCggICAAAAA==.Caythus:BAACNQAFFH8jAAQVAAcKGCH/AwA9AgAVAAYKrx3/AwA9AgAWAAIKJiaQAwDeAAAUAAEKAACtBgBqAAA1AAQKfywABBYACQrIJsEBAGMDABYACQq4I8EBAGMDABUACAq0JpkPAFIDABQAAQoAAHAiAGYAAAAA.Caythuz:BAAANQAECgYICwABNQAFFAcIIwAVABghAA==.',
Ce='Celeana:BAAANQAECgEIAQAAAA==.Celencia:BAAANQADCgEIAQAAAA==.Ceryin:BAAANQADCgYICAAAAA==.',
Ch='Chadmcguffin:BAAANQADCgEIAQAAAA==.Chainheal:BAAANQABCgIIAgAAAA==.Chakabad:BAAANQAECgQIBQAAAA==.Chalgah:BAAANQAECgIIBAAAAA==.Charnyanya:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Chenahala:BAAANQAECgQIBQAAAA==.Chloe:BAAANQADCggICAAAAA==.Chåni:BAABNQAECn86AAISAAkKZx4MDAAeAwASAAkKZx4MDAAeAwAAAA==.',
Ci='Cimerone:BAAANQABCgYICQAAAA==.',
Ck='Ckayz:BAAANQAECgIIAgAAAA==.',
Cl='Clam:BAABNQAECn8XAAMJAAcKwggWqwCqAQAJAAcKwggWqwCqAQAXAAUKegJjXACwAAAAAA==.Claw:BAAANQAECggIDAABNQAFFAUIDAAFAKsQAA==.Clisa:BAAANQABCgEIAQAAAA==.',
Co='Co:BAAANQAECgUIDAAAAA==.Coldstonez:BAAANQADCggIEgAAAA==.Collette:BAAANQADCggIEQAAAA==.Conanascus:BAAANQADCgcIDgABNQAECggIKgAYAFYPAA==.Confessorr:BAAANQADCgYIBQABNQAECgUIDwABAAAAAA==.Corrupteded:BAAANQAECgEIAQAAAA==.',
Cr='Crimsonmana:BAAANQADCgMIAwAAAA==.Crispysock:BAAANQAECgUIEgAAAA==.Crowe:BAAANQAECgMIBAAAAA==.',
Cy='Cynderr:BAABNQAECn8aAAIZAAcKAhNZGADBAQAZAAcKAhNZGADBAQAAAA==.',
Da='Daisymayhem:BAAANQABCgcICAAAAA==.Daquilla:BAAANQADCgUICgAAAA==.Darkfury:BAAANQAECgQIBAAAAA==.Darkisis:BAAANQAECgUICwAAAA==.Darknara:BAABNQAECn8kAAMLAAkKBR1gIACuAgALAAkKBR1gIACuAgAFAAMKixO3sQCJAAAAAA==.Darkterror:BAAANQAECgQIBAABNQAECgUICwABAAAAAA==.Darkzy:BAAANQAECgEIAwAAAA==.Dartol:BAAANQAECgMIBwAAAA==.Dasubertakem:BAAANQADCgYIDQAAAA==.Dawni:BAABNQAECn8cAAQOAAgKGw63LQAxAQAOAAYKzQq3LQAxAQAZAAIKdhACMwByAAAaAAEKiASdJQAsAAAAAA==.',
Dd='Ddz:BAAANQADCgUIBQAAAA==.',
De='Deathjeff:BAABNQAECn8YAAIGAAkK3SQlBwBvAwAGAAkK3SQlBwBvAwAAAA==.Deathsgates:BAAANQAECgQICAABNQAFFAIIBQAYADUQAA==.Detala:BAAANQADCgYICQAAAA==.',
Di='Didymus:BAAANQADCgUIBQAAAA==.Diereth:BAAANQABCgIIAgAAAA==.Dimos:BAAANQAECgUIDQAAAA==.Dinoll:BAAANQAECgQIBgAAAA==.Dirtwhistle:BAABNQAECn8qAAIbAAkKZSQfAgCaAwAbAAkKZSQfAgCaAwAAAA==.',
Dr='Dracont:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Dragondh:BAACNQAFFH8FAAIRAAIKSQmNGAB2AAARAAIKSQmNGAB2AAA1AAQKfyIAAhEACQqMG7UkAHMCABEACQqMG7UkAHMCAAAA.Dranlu:BAAANQADCgYICQAAAA==.Drazsi:BAAANQAECgUICwAAAA==.Drekkara:BAAANQADCgQIBAABNQAECgMICQABAAAAAA==.Drosi:BAABNQAECn8hAAIMAAcKGxJbtQCtAQAMAAcKGxJbtQCtAQAAAA==.Drovaal:BAAANQADCgUIBQAAAA==.',
Dy='Dyromancer:BAAANQADCgIJAgAAAA==.',
['Då']='Dåmmn:BAAANQAECgEIAQAAAA==.',
Ea='Earthesance:BAAANQAECgIIAwAAAA==.',
Eb='Ebeb:BAAANQAECgUIDgAAAA==.',
Ed='Edgedweenie:BAAANQADCgQIBAAAAA==.',
Ei='Eiwe:BAAANQADCgYICQAAAA==.',
El='Eleanne:BAABNQAECn8WAAMPAAcK0BDfTACqAQAPAAcK0BDfTACqAQAcAAMKdRCOWACgAAAAAA==.Electricfury:BAAANQAECgUIBQAAAA==.Elementalism:BAAANQADCgQIBAAAAA==.Ellebasi:BAAANQAECgIIAwAAAA==.Ellebazy:BAABNQAECn8dAAINAAcK/hOwKQCMAQANAAcK/hOwKQCMAQAAAA==.',
Em='Emmri:BAAANQAECgUIDQAAAA==.',
En='Enazen:BAAANQAECgYIEwAAAA==.Enlighthyn:BAABNQAECn8aAAIKAAkK0R7MHwDuAgAKAAkK0R7MHwDuAgABNQAFFAUICAAdAKQaAA==.',
Er='Erlas:BAAANQAECgMIAwAAAA==.Erui:BAAANQAECgQIBQAAAA==.',
Es='Esmeluz:BAAANQADCgMIAwAAAA==.',
Et='Etorion:BAAANQADCggIDQAAAA==.Etrexxig:BAAANQADCgcJCwAAAA==.',
Ev='Evilrayne:BAABNQAECn8yAAITAAgKxRh4jABmAgATAAgKxRh4jABmAgAAAA==.',
Fa='Fanfiction:BAABNQAECn8YAAMOAAgK6xI5GwATAgAOAAgK6xI5GwATAgAZAAEKAABtQQAmAAAAAA==.Fatherfingur:BAAANQADCgMIBAAAAA==.',
Fe='Featara:BAAANQADCgEIAQAAAA==.Feather:BAAANQAECgYIEQAAAA==.Felmonger:BAAANQAECgQIBwAAAA==.Feloak:BAABNQAECn8WAAIeAAcKZAqsFgA/AQAeAAcKZAqsFgA/AQAAAA==.Feredir:BAAANQAECgIIAwAAAA==.',
Fi='Fires:BAABNQAECn8iAAQTAAgKIh/HWwDIAgATAAgKwx7HWwDIAgAfAAQK5x1ZFwA+AQAgAAEKAAAzDQA4AAAAAA==.Fistandilius:BAAANQAECgYIEgAAAA==.',
Fo='Folexper:BAAANQADCggIDwAAAA==.',
Fr='Frostman:BAABNQAECn8oAAMLAAgKNyNXEQAgAwALAAgKNyNXEQAgAwAGAAEKAAB4mwBTAAAAAA==.',
Fu='Furryfury:BAABNQAECn8vAAMQAAkKHBv2DQCgAgAQAAkKHBv2DQCgAgAIAAEKAAATagAyAAAAAA==.Fusrodah:BAABNQAECn8gAAMOAAgK7Rb9GAAtAgAOAAgK7Rb9GAAtAgAZAAEKAAAlOQBBAAAAAA==.Fuzzyewok:BAABNQAECn8hAAIKAAcKgx6UQABgAgAKAAcKgx6UQABgAgAAAA==.',
Ga='Gabaghoul:BAABNQAECn8qAAILAAgKVxuLLwBSAgALAAgKVxuLLwBSAgAAAA==.Gameshark:BAAANQAECgYIEgAAAA==.Gawdzirra:BAAANQAECgcIDQAAAA==.Gaylordgerva:BAAANQAECgEIAQAAAA==.Gaz:BAAANQAECggIJgAAAQ==.',
Ge='Geauxaway:BAAANQADCgQIAgAAAA==.George:BAAANQADCggIGQAAAA==.',
Gh='Ghazghküll:BAAANQAECgQIBAAAAA==.Ghulrokk:BAAANQAECgIIAgAAAA==.',
Gi='Gilidan:BAAANQABCgIIAgAAAA==.',
Gl='Gluum:BAAANQADCgYICwAAAA==.',
Go='Gohibasi:BAAANQAECgIIAwAAAA==.Goops:BAAANQADCgEIAQAAAA==.Gorzarpixx:BAAANQAECgEIAQAAAA==.Gossamerfeet:BAAANQAECggIEQAAAA==.',
Gr='Graceosilver:BAAANQAECgQICAAAAA==.Gregnor:BAABNQAECn8hAAUCAAcKQBLUEQDgAQACAAcKQBLUEQDgAQAPAAYKVAYsawAaAQAhAAQKTgh7RACbAAAcAAMKuAMGZABvAAAAAA==.Gremöry:BAABNQAECn8WAAMiAAcKhA/phgB1AQAiAAcKhA/phgB1AQAjAAYKwRHKmABjAQAAAA==.Grippysock:BAAANQADCgYICQAAAA==.Grover:BAABNQAECn8gAAIMAAgKZBUCgAAkAgAMAAgKZBUCgAAkAgAAAA==.Grumpybunbun:BAABNQAECn8gAAIdAAkK1xGRUgAoAgAdAAkK1xGRUgAoAgAAAA==.Grüm:BAAANQAECgIIAwAAAA==.',
Gu='Guldangraham:BAAANQAECggIAgABNQAECggIDwABAAAAAA==.Guppy:BAAANQADCgYIBgAAAA==.',
Gy='Gyorge:BAAANQADCgUIBQAAAA==.',
['Gå']='Gårrus:BAABNQAECn8aAAIJAAcK4xo2bAA3AgAJAAcK4xo2bAA3AgAAAA==.',
Ha='Haarl:BAAANQADCgcIBwAAAA==.Hairypotter:BAAANQADCgcIFAABNQAECgQIBQABAAAAAA==.Halazzi:BAAANQAECgEIAgAAAA==.Haldar:BAAANQAECgUICwAAAA==.Hallie:BAAANQAECgQICAAAAA==.Harlu:BAABNQAECn8UAAIjAAYKdgUFtwAgAQAjAAYKdgUFtwAgAQAAAA==.Hartbroke:BAABNQAECn8XAAIMAAYKTRvqngDfAQAMAAYKTRvqngDfAQAAAA==.Haunter:BAAANQAECgQIDAABNQAECggIGQAcAPcdAA==.Hayeon:BAAANQAECgEIAQAAAA==.',
He='Helbourne:BAAANQAECgYIEgAAAA==.',
Hi='Hijjiup:BAAANQADCgQIBAAAAA==.',
Ho='Holybunbun:BAAANQAECgYICQAAAA==.Holyrollerz:BAAANQADCgYIBgAAAA==.Homeydagreat:BAAANQAECgEIAQAAAA==.',
Hu='Huna:BAAANQADCgYIBgABNQAECgQIFQAkAOcaAA==.Hunsx:BAAANQAECgUICAAAAA==.Huntingpups:BAAANQADCggICAAAAA==.',
Hw='Hwanwok:BAABNQAECn8aAAIIAAcKvxRxKwC8AQAIAAcKvxRxKwC8AQAAAA==.',
['Hâ']='Hânzö:BAAANQADCgMIAwAAAA==.',
Ia='Iamwarlock:BAAANQADCgIIAgAAAA==.',
Ic='Icemage:BAAANQAECgMIBgAAAA==.',
Id='Ideal:BAAANQADCgEIAQAAAA==.',
Ig='Ignited:BAAANQAECgMIBAAAAA==.',
Im='Imadragon:BAABNQAECn8jAAIZAAgKtw0WGADFAQAZAAgKtw0WGADFAQAAAA==.Imbac:BAAANQAECgEIAQAAAA==.Imdeadguy:BAABNQAECn8jAAIbAAgK3x/YBgDxAgAbAAgK3x/YBgDxAgAAAA==.',
In='Inarian:BAAANQADCgYIBgAAAA==.',
Ir='Irilara:BAAANQADCgcIHAAAAA==.Ironhelmhtr:BAAANQAECgEIAQAAAA==.',
Is='Istian:BAAANQADCgQIBgAAAA==.',
Ja='Jaayk:BAAANQAECgcIDQAAAA==.Jace:BAAANQAECgIIAgAAAA==.Jazlee:BAABNQAECn8UAAIbAAYK0B0TFQDSAQAbAAYK0B0TFQDSAQAAAA==.',
Je='Jealous:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Jefflock:BAAANQADCgEIAQABNQAECgUIEwABAAAAAA==.Jezmund:BAABNQAECn8ZAAIcAAUK+RjLNQBoAQAcAAUK+RjLNQBoAQAAAA==.',
Ji='Jinathy:BAABNQAECn8eAAIMAAgK+RB3pQDQAQAMAAgK+RB3pQDQAQAAAA==.Jinxed:BAAANQADCgYIBgAAAA==.',
Jo='Jolyñ:BAAANQAECgcIDgABNQAECggIGAAlAHYMAA==.',
Ju='Juaranir:BAABNQAECn8eAAIhAAgKYxP2GwC+AQAhAAgKYxP2GwC+AQAAAA==.Judgementall:BAAANQADCgQIBAAAAA==.Juicébòx:BAAANQAECgIIAgAAAA==.Justac:BAAANQAECgMIAwABNQAECgUICAABAAAAAA==.Justdrood:BAAANQAECgUICAAAAA==.',
Jw='Jwst:BAAANQAECgMIAwAAAA==.',
['Jà']='Jàß:BAAANQAECgYIDQAAAA==.',
['Já']='Jáß:BAABNQAECn8ZAAIKAAkK2R15GgALAwAKAAkK2R15GgALAwAAAA==.',
['Jä']='Jäb:BAAANQAECgUIBwAAAA==.',
Ka='Kahleah:BAAANQADCgcIBAAAAA==.Kaldonor:BAABNQAECn8qAAIGAAgK2g++PQDPAQAGAAgK2g++PQDPAQAAAA==.Kalenia:BAABNQAECn8uAAIiAAgKsiLzGAANAwAiAAgKsiLzGAANAwAAAA==.Kalvayre:BAAANQAECgQICQAAAA==.Kanzoorb:BAABNQAECn8jAAITAAkK1xx5UgDbAgATAAkK1xx5UgDbAgAAAA==.Kareshka:BAABNQAFFH8HAAMfAAUKFQ2NBADIAAATAAMKAwf6OQDXAAAfAAMKVRGNBADIAAAAAA==.Karinea:BAEANQAECgUIEgAAAA==.Karpana:BAEBNQAECn8lAAMNAAYKBBoLLwBiAQAMAAYKhBP50gBvAQANAAUKZxwLLwBiAQAAAA==.Karreena:BAAANQADCgYIBgAAAA==.Karworg:BAAANQADCggIFQAAAA==.Kashir:BAAANQAECgQICgAAAA==.Kashira:BAAANQADCggIEgABNQAECgQICgABAAAAAA==.Kathelee:BAAANQAECgcIDQAAAA==.Kazimirah:BAAANQAECgEIAQAAAA==.Kazrael:BAAANQAECgQICAAAAA==.',
Ke='Keekat:BAAANQADCggIGAAAAA==.Kevinbeacon:BAEANQAECgYIEgAAAA==.',
Kh='Kharnij:BAAANQAECgQIBQAAAA==.Khaíbit:BAAANQADCgYIBgAAAA==.Khonsu:BAABNQAECn8fAAQVAAcKqRLQowCIAQAVAAYKvxPQowCIAQAUAAEKOQ3bKQBEAAAWAAEKEBMHcAA/AAAAAA==.Khryy:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.',
Ki='Kiamei:BAAANQAECgEIAQAAAA==.Kikora:BAAANQADCgcIDQAAAA==.Kittykitty:BAABNQAECn8jAAMiAAgKzB/xJADQAgAiAAgKzB/xJADQAgAjAAUKghZNpgBEAQAAAA==.',
Ko='Kolzane:BAECNQAFFH8RAAIJAAcKuCOSAAC5AgAJAAcKuCOSAAC5AgA1AAQKfyAAAgkACQpXJvYLAH0DAAkACQpXJvYLAH0DAAAA.',
Kr='Krezz:BAAANQAECgYIEgAAAA==.',
Ku='Kumojo:BAAANQADCggICAAAAA==.Kurna:BAAANQADCgEIAQAAAA==.Kuulas:BAACNQAFFH8MAAIJAAUKYQ8hDgBtAQAJAAUKYQ8hDgBtAQA1AAQKfx4AAgkACQqhGqcvANwCAAkACQqhGqcvANwCAAAA.',
Ky='Kynlyn:BAAANQADCgQIBAAAAA==.Kyth:BAABNQAECn8gAAMNAAgKbRthGAAyAgANAAgKbRthGAAyAgAMAAEKAADepQExAAAAAA==.Kythlock:BAAANQADCgYIBQABNQAECggIIAANAG0bAA==.Kythtok:BAAANQADCgYICAABNQAECggIIAANAG0bAA==.',
La='Lanx:BAAANQAECgIIAgAAAA==.Laquatas:BAAANQAECgcIEwAAAA==.Laylanduin:BAAANQADCgEIAQABNQAECgkJGAAGAN0kAA==.',
Le='Leadfarmer:BAAANQAECggIAgAAAA==.Lenash:BAAANQAECgIIAgABNQABCgIIBAABAAAAAA==.',
Li='Lifebloomer:BAAANQAECgEIAQABNQAFFAYIHQALAPolAA==.Lightguard:BAABNQAECn8ZAAIMAAgKDBNnmgDpAQAMAAgKDBNnmgDpAQAAAA==.Likesitruff:BAAANQADCgcICQAAAA==.Lilolock:BAAANQAECgUIEgAAAA==.Littlehell:BAAANQAECggIDwAAAA==.',
Lo='Lothrik:BAAANQAECgYICwAAAA==.',
Lu='Lucaafer:BAAANQADCgYIFwABNQAECgkJGwARAIQXAA==.Luda:BAAANQAECgYIDgABNQAECgcIDQABAAAAAA==.Ludaa:BAAANQAECgQICQABNQAECgcIDQABAAAAAA==.Ludahealz:BAAANQADCgEIAQABNQAECgcIDQABAAAAAA==.Lunamoonclaw:BAAANQAECgYJEAAAAA==.Lunaspire:BAAANQADCgIIAgAAAA==.',
Ly='Lyntrax:BAAANQAECgQIBgAAAA==.Lyssandria:BAAANQAECgUICQAAAA==.Lyzoldas:BAABNQAECn8WAAIMAAgKyxQSlAD3AQAMAAgKyxQSlAD3AQAAAA==.',
['Lá']='Lárry:BAAANQADCgUIBgAAAA==.',
['Lö']='Löwryder:BAAANQAECgQICgAAAA==.',
Ma='Madness:BAAANQADCgYIBwABNQAECggIGwAjAO4KAA==.Mae:BAAANQAECgcIEAABNQABCgIIAgABAAAAAA==.Maemura:BAAANQAECgIIAwAAAA==.Magdalaiina:BAABNQAECn8YAAIKAAYKYCBFTAA1AgAKAAYKYCBFTAA1AgAAAA==.Magicdaisee:BAAANQADCgYIBgAAAA==.Magusman:BAAANQAECgcIBwABNQAECggIKAALADcjAA==.Magîkarp:BAAANQAECgUIEQAAAA==.Malchromatus:BAABNQAECn8kAAMOAAgKOQsoJQCUAQAOAAgKOQsoJQCUAQAZAAcKWwZcIQBCAQAAAA==.Marcosio:BAAANQAECgMIBQAAAA==.Marmaladia:BAAANQADCggIDQAAAA==.Marsala:BAABNQAECn8XAAIPAAkKaQv6SQC7AQAPAAkKaQv6SQC7AQAAAA==.Mavik:BAAANQAECggIAgAAAA==.Maylater:BAAANQAECgMIAwABNQAECggIFAAIAL4RAA==.',
Me='Mearkman:BAAANQAECgQIDAAAAA==.Meatyfajita:BAABNQAECn8eAAIKAAgKAiZRDABkAwAKAAgKAiZRDABkAwAAAA==.Meinfurion:BAAANQAECgYIEgAAAA==.Meinstrom:BAAANQADCggICAABNQAECgYIEgABAAAAAA==.Meladie:BAAANQAECgEIAQAAAA==.Melevolent:BAAANQABCgQIBAAAAA==.Memedecay:BAABNQAECn8rAAQFAAgKJyKrHgDRAgAFAAgKJyKrHgDRAgAGAAcKUxJySACVAQALAAEKAAAuugBQAAAAAA==.Memeonhuntër:BAAANQADCgMIAwABNQAECggIKwAFACciAA==.Merit:BAAANQADCggIEAABNQAECggIHwARAI8WAA==.Merlinthos:BAABNQAECn8YAAITAAgKMASLEwFoAQATAAgKMASLEwFoAQABNQAECggIKgAYAFYPAA==.Messra:BAAANQADCgMIAwAAAA==.Metaljack:BAABNQAECn8hAAMfAAcKbiGeDADrAQATAAcKOx7WhwBuAgAfAAUKqCCeDADrAQAAAA==.',
Mi='Miasma:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Midith:BAAANQADCgYIBgAAAA==.Minecraft:BAABNQAECn8dAAIkAAkKSxm4BwB0AgAkAAkKSxm4BwB0AgAAAA==.Mingyue:BAAANQAECgQIBAABNQAECggIJQAPADoVAA==.Mirajåne:BAACNQAFFH8HAAIEAAMK4RDDDQDzAAAEAAMK4RDDDQDzAAA1AAQKfzcABAQACQr2HNsOAAEDAAQACQr2HNsOAAEDAB0ABQqyEaakACEBACYAAQq6AiQtACkAAAAA.Mishaweha:BAAANQAECgcIEgAAAA==.Missdowtfire:BAAANQADCgIIAgAAAA==.Mitos:BAAANQADCgQICQAAAA==.',
Mo='Modar:BAABNQAECn8gAAMiAAkKYRM5RgBGAgAiAAkKYRM5RgBGAgAjAAMKsgQc4wDLAAAAAA==.Monkas:BAAANQAECgEIAQAAAA==.Moonhoof:BAAANQADCgIIAgAAAA==.Moonrid:BAAANQADCggIEwAAAA==.Mornanden:BAAANQAECgQIBAAAAA==.',
Mu='Musterd:BAAANQADCgYJDQAAAA==.',
['Må']='Måddløck:BAAANQADCgYIDAAAAA==.',
Na='Nahray:BAAANQADCgQIBAAAAA==.Namaera:BAAANQADCgcIBwAAAA==.Navatath:BAAANQAECgMIBQABNQAFFAcIHwATAL8kAA==.',
Ne='Neiidra:BAAANQAECgUIBgAAAA==.Nepheleah:BAACNQAFFH8FAAIMAAIKNhdlHwCjAAAMAAIKNhdlHwCjAAA1AAQKfyoAAgwACQqDIkMPAI0DAAwACQqDIkMPAI0DAAAA.Nesca:BAAANQAECgYIEQAAAA==.Nesmoth:BAAANQAECgQICgAAAA==.Ness:BAAANQAECgYIEwAAAA==.Nessecity:BAAANQADCgYIEAAAAA==.',
Ni='Nicolassaban:BAAANQADCgEIAQAAAA==.Nicolina:BAAANQADCggIDQAAAA==.Niiborracho:BAABNQAECn8eAAMIAAgKHQ73LgCbAQAIAAgKHQ73LgCbAQAQAAUKNBFzLQD8AAAAAA==.Niiko:BAAANQAECgQIDwAAAA==.',
No='No:BAAANQADCgUJBQABNQAECgkJJwADAOIhAA==.Nobullsheep:BAAANQABCggIBwAAAA==.Nommy:BAAANQAECgcIDwABNQAECggILQAJADUbAA==.Norntrox:BAAANQAECgYIEAAAAA==.Nothannah:BAABNQAECn8gAAIcAAkKXRA7JQD2AQAcAAkKXRA7JQD2AQAAAA==.',
Ns='Nsshaman:BAAANQADCgUIBQAAAA==.',
Od='Odyssey:BAAANQADCggJCAABNQAECggIHwARAI8WAA==.',
Og='Ogreatsxtra:BAAANQAECgQIBwAAAA==.',
Ol='Ol:BAAANQAECgYICwAAAA==.',
On='Onethiccyboi:BAAANQADCgEIAQAAAA==.Onix:BAAANQAECgcICAABNQAECggIGQAcAPcdAA==.',
Or='Orctism:BAAANQAECgMIAwAAAA==.',
Ow='Owlsonatotem:BAAANQAECgcIDgAAAA==.',
Oz='Ozhawk:BAAANQAECgUIBwAAAA==.',
Pa='Padreburrito:BAEANQADCgYICwABNQAFFAYIDAAcAMceAA==.Pakno:BAAANQAECgUIBQAAAA==.Pamely:BAABNQAECn83AAIMAAkKCSB0IgA4AwAMAAkKCSB0IgA4AwAAAA==.',
Pe='Perices:BAAANQADCgYIBgAAAA==.',
Ph='Pharmit:BAABNQAECn8kAAMUAAcK+iUJAgAVAwAUAAcK+iUJAgAVAwAVAAEKXSGYLAFbAAAAAA==.Phiarce:BAAANQAFFAEIAQAAAA==.',
Pl='Pletua:BAAANQAECgYICAAAAA==.',
Po='Porterhouse:BAAANQADCgUIBwAAAA==.Potatoad:BAAANQAECgIIBAAAAA==.',
Pw='Pwags:BAAANQADCgUJBQAAAA==.',
Py='Pyragosa:BAABNQAECn8aAAITAAgKtBGCwQD/AQATAAgKtBGCwQD/AQAAAA==.Pyramys:BAAANQABCgQIAwABNQAECgcIGgAHAH8gAA==.',
['Pà']='Pàt:BAABNQAECn8dAAIEAAgKlxmKGACLAgAEAAgKlxmKGACLAgAAAA==.',
['Pâ']='Pândâmoníum:BAAANQAECgMIBQAAAA==.',
['På']='Påimon:BAAANQADCggJEAAAAA==.',
Qu='Quintin:BAEANQADCgIJAgABNQAECgkJIgALAAImAA==.',
Ra='Racavis:BAAANQADCgMIAwAAAA==.Ralsei:BAAANQAECgEIAQAAAA==.',
Re='Reach:BAAANQADCgYICgABNQAECgcIDQABAAAAAA==.Readdyy:BAAANQAECgcIBwAAAA==.Real:BAABNQAECn8fAAITAAgKvhtsfACFAgATAAgKvhtsfACFAgABNQABCgIIAgABAAAAAA==.Realia:BAAANQAECgcICAAAAA==.Reda:BAAANQAECgUIBQAAAA==.Redangus:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Reikio:BAAANQADCgIIAgAAAA==.Reptar:BAAANQADCgcIBwABNQAFFAYIGQAPABQcAA==.Revoke:BAABNQAECn8XAAIMAAgKJwnlzgB3AQAMAAgKJwnlzgB3AQAAAA==.',
Ro='Rocknrolln:BAAANQADCgYIDAAAAA==.Rokubora:BAABNQAECn8gAAMjAAgK2BOrUQAvAgAjAAgK2BOrUQAvAgAiAAYKFAsYqgAZAQAAAA==.Rongyi:BAAANQAECgEIAQABNQAECggIJQAPADoVAA==.Roronoa:BAAANQADCgYIBwAAAA==.Roßyn:BAABNQAECn8cAAMEAAkKjg8lJwDvAQAEAAgKwg8lJwDvAQAdAAUK6QgOrgAHAQAAAA==.',
Ru='Rubah:BAAANQAECgcIEwAAAA==.Rundail:BAAANQADCgQIBAAAAA==.Ruroni:BAAANQAECgUIEgAAAA==.',
Ry='Ryniel:BAAANQAECgIIAgAAAA==.',
['Ré']='Rédundant:BAAANQAECgYIDAABNQAECgcIDQABAAAAAA==.',
['Rì']='Rìzz:BAABNQAECn8lAAIjAAgKnR1YNACkAgAjAAgKnR1YNACkAgAAAA==.',
Sa='Sabrinalee:BAAANQADCgEJAQAAAA==.Saintdeamon:BAAANQADCgYIDAAAAA==.Sak:BAAANQADCgUIBQAAAA==.Salk:BAAANQADCgYIBgAAAA==.Sanasta:BAAANQAECgIIAwABNQAECgQIBwABAAAAAA==.Sannaggi:BAAANQAECgYIDgAAAA==.Sarahnox:BAABNQAECn8ZAAIcAAgKjRr+GgBdAgAcAAgKjRr+GgBdAgAAAA==.Saramoon:BAABNQAECn8VAAIHAAcKawbvKgBnAQAHAAcKawbvKgBnAQAAAA==.Sarayana:BAAANQABCgIIAwAAAA==.Sargent:BAAANQADCggIGAAAAA==.Saryaa:BAAANQAECgcICwAAAA==.Sashchi:BAABNQAECn8bAAIIAAcKFRLmMgB6AQAIAAcKFRLmMgB6AQAAAA==.Sassenach:BAAANQAECgEIAwAAAA==.Saudelber:BAAANQAECgUIBgAAAA==.',
Sc='Schanks:BAABNQAECn8WAAIYAAgKkhzPFgDCAgAYAAgKkhzPFgDCAgAAAA==.Scoliosisstu:BAAANQADCggICAAAAA==.Scrotius:BAAANQABCgQIBQAAAA==.',
Se='Sedaelina:BAAANQAECgEIAQABNQAECgkJIAAcAF0QAA==.Sehmet:BAAANQAECgQICgAAAA==.Seliria:BAABNQAECn8hAAIMAAcKaBKRswCyAQAMAAcKaBKRswCyAQAAAA==.Seoulmate:BAABNQAECn8lAAIPAAgKOhUrNgA2AgAPAAgKOhUrNgA2AgAAAA==.Sera:BAAANQAECgcIEwAAAA==.Severûs:BAAANQADCgEIAQAAAA==.',
Sh='Shadoezz:BAAANQADCgQIBAAAAA==.Shadowk:BAAANQABCgIIAgAAAA==.Shamsicle:BAAANQADCgMIAwAAAA==.Shaye:BAAANQAECgMICQAAAA==.Shelari:BAAANQADCgEIAQAAAA==.Sherai:BAAANQADCgIIAgAAAA==.Shieldbro:BAAANQADCgEIAQABNQAECggIDwABAAAAAA==.Shimone:BAAANQADCgEIAQAAAA==.Shinybeef:BAAANQADCgcIFgAAAA==.Shiryo:BAAANQAECgQIBAAAAA==.Shotfoot:BAABNQAECn8oAAIJAAkKshd0OgC5AgAJAAkKshd0OgC5AgAAAA==.Shurae:BAAANQADCgYIBgAAAA==.Shwang:BAAANQAECgUIEgAAAA==.',
Si='Sihåya:BAAANQAECgcIDwAAAA==.Silbergrad:BAAANQADCggIFQAAAA==.Silentio:BAABNQAECn8qAAIYAAgKVg/tMQASAgAYAAgKVg/tMQASAgAAAA==.Silihunt:BAABNQAECn8pAAMSAAgK9Re+JwADAgASAAcKIhm+JwADAgARAAgKrxL4OQDgAQAAAA==.Sinofwrath:BAAANQAECgcIDQAAAA==.Sinsidious:BAAANQAECgYICwAAAA==.Siwin:BAECNQAFFH8MAAIcAAYKxx6dAgAxAgAcAAYKxx6dAgAxAgA1AAQKfyUAAxwACQoSJjkDAJQDABwACQoSJjkDAJQDAA8AAgoAAPWZAGwAAAAA.',
Sk='Skribb:BAABNQAECn8hAAIKAAcKWyS9IwDaAgAKAAcKWyS9IwDaAgAAAA==.',
Sl='Slapchóp:BAABNQAECn8ZAAIjAAcKkB3DPwBzAgAjAAcKkB3DPwBzAgAAAA==.',
Sm='Smiley:BAACNQAFFH8QAAIdAAYKcxPKCQDnAQAdAAYKcxPKCQDnAQA1AAQKfyEAAh0ACQocGBZCAGACAB0ACQocGBZCAGACAAE1AAUUBgoQAB0AcxMA.Smoko:BAAANQAECgMJBAAAAA==.',
Sn='Sneakyboi:BAAANQAECggIDwAAAA==.Snorlax:BAABNQAECn8ZAAQcAAgK9x3KFgCIAgAcAAgK9x3KFgCIAgAhAAIKFRYrRwCLAAAPAAIKYBVooABYAAAAAA==.Snowsu:BAACNQAFFH8aAAMVAAcKDyMnAwBUAgAVAAYKwyInAwBUAgAWAAIKJiHMBQDCAAA1AAQKfy8AAxUACQqrJkoBAOkDABUACQqZJkoBAOkDABYABwqUHdAKAEkCAAAA.Snowxstorm:BAABNQAECn8cAAILAAcKDxpOOgAaAgALAAcKDxpOOgAaAgAAAA==.',
So='Soaringeagle:BAAANQABCgYICgAAAA==.Solidvodka:BAAANQAECgUIEwAAAA==.Solusrush:BAAANQABCgEIAQAAAA==.Souldecay:BAABNQAECn8eAAIFAAcKmg1xZgBzAQAFAAcKmg1xZgBzAQAAAA==.',
Sp='Splashzone:BAABNQAECn8ZAAIiAAcKmwlxnQA5AQAiAAcKmwlxnQA5AQAAAA==.Splits:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.',
St='Staqua:BAAANQAECgQICAAAAA==.Stateomatter:BAAANQAECgcIEwAAAA==.',
Su='Suanni:BAAANQADCgQIBAABNQAECggIJQAPADoVAA==.Summdari:BAABNQAECn8gAAIeAAgKzRXMCwALAgAeAAgKzRXMCwALAgAAAA==.Summrot:BAAANQAECgcIEwAAAA==.Sunfrostt:BAAANQAECgQIBgAAAA==.',
Sy='Syanana:BAAANQADCgYICQAAAA==.Sylvalesta:BAAANQAECgQICAAAAA==.',
Ta='Tacgnol:BAAANQADCgYIBgAAAA==.Talyon:BAAANQAECgYIDAAAAA==.Tanayla:BAAANQADCgYIBgAAAA==.Tatertotem:BAABNQAECn8XAAMiAAkKAxRyRgBFAgAiAAkKAxRyRgBFAgAnAAIKagiWLwBtAAAAAA==.',
Td='Tdogx:BAAANQAECgQIBAAAAA==.',
Te='Teal:BAAANQAECgIIAwAAAA==.Tekeeladin:BAAANQAECgMIAwABNQAFFAIIBQAJAJsdAA==.Tekeelà:BAABNQAECn8eAAIJAAcKyiDdTACFAgAJAAcKyiDdTACFAgABNQAFFAIIBQAJAJsdAA==.Tekelemental:BAAANQAECgUIEAAAAA==.Tempestra:BAAANQAECgUICwAAAA==.Tenebria:BAABNQAECn8vAAIlAAkKYiCNAQBOAwAlAAkKYiCNAQBOAwAAAA==.Terrorhungry:BAAANQAECgUICgAAAA==.',
Th='Thalstrasza:BAABNQAECn8dAAIVAAcKKg1roQCOAQAVAAcKKg1roQCOAQAAAA==.The:BAAANQAECgQICgAAAA==.Thedevilsown:BAAANQADCgYICgAAAA==.Thedrizzle:BAABNQAECn8cAAMTAAgK7xXs2wDNAQATAAcKFBTs2wDNAQAfAAIKzxsuLwCCAAAAAA==.Theodiseus:BAAANQADCgUIBQAAAA==.Thugrodent:BAAANQAECggJAQAAAA==.Thundrfury:BAAANQADCgQIBQAAAA==.Thysane:BAAANQADCgEIAQAAAA==.',
Ti='Tietus:BAAANQAECgUIBgAAAA==.',
Tl='Tlanimass:BAABNQAECn8UAAIbAAYKABMaHwBVAQAbAAYKABMaHwBVAQAAAA==.',
To='Tolac:BAAANQADCgEIAQAAAA==.',
Tr='Treeko:BAAANQADCggICAABNQAFFAYICgAVAI0TAA==.Treyna:BAAANQADCgMIAwAAAA==.',
Ts='Tsu:BAAANQAECgcIDgAAAA==.Tsyubaki:BAAANQAECgQICwAAAA==.',
Tu='Tulisse:BAAANQAECgEIAQAAAA==.',
Tw='Twerkngherkn:BAAANQAECgYICgAAAA==.',
Ty='Tybalt:BAABNQAECn8kAAInAAkKsCKjAgB9AwAnAAkKsCKjAgB9AwAAAA==.Tynkxstrazza:BAAANQADCgEIAQAAAA==.Tyrandaz:BAAANQAECggIEQAAAA==.',
Ul='Uldric:BAAANQAECgYIEgAAAA==.',
Un='Undeaddude:BAAANQAECgUICAAAAA==.Unslayable:BAAANQAECgQICAAAAA==.',
Uz='Uzzy:BAAANQAECgQIBQAAAA==.',
Va='Valandir:BAABNQAECn8ZAAMMAAcK7Q2OwwCPAQAMAAcK7Q2OwwCPAQANAAMKOgUrWwBqAAAAAA==.Valyst:BAAANQAECgEIAQAAAA==.Varya:BAAANQABCgQIBQAAAA==.',
Ve='Veliry:BAAANQADCgYIDwAAAA==.Verbera:BAACNQAFFH8SAAIcAAUKURkFBgCqAQAcAAUKURkFBgCqAQA1AAQKfyMAAxwACQqLFPUbAFMCABwACQqLFPUbAFMCAA8ABgpsBWR6AN0AAAAA.Verrenth:BAAANQAECggIBgABNQAECggIDwABAAAAAA==.',
Vi='Viduus:BAAANQAECgMIAwAAAA==.Vigol:BAAANQADCgQJBAAAAA==.Vivec:BAAANQADCgMIAwAAAA==.',
Vm='Vmaoh:BAAANQADCggIEAAAAA==.',
Vo='Voidrodent:BAAANQAECggIBgAAAA==.Voidwithin:BAAANQAECgQIBgAAAA==.Voljinforeva:BAAANQADCgQJBgAAAA==.',
Vu='Vulfox:BAAANQAECgMIBQABNQAECggIGgAdAOIYAA==.',
Wa='Wakenbake:BAAANQADCgUIBQAAAA==.Wandiferous:BAAANQAECgUIDwAAAA==.Warwickk:BAAANQABCgIIAgABNQADCgUIBQABAAAAAA==.',
Wf='Wfreemen:BAAANQADCgQIBAAAAA==.',
Wh='Who:BAAANQAECgQIBAAAAA==.',
Wi='Wickedholi:BAAANQAECgcIBwABNQAFFAYICgAVAI0TAA==.Wickedsmaht:BAACNQAFFH8KAAMVAAYKjRMyGAA4AQAVAAQKShUyGAA4AQAWAAIK0BFFDgCcAAA1AAQKfzUABBUACQqrIwwdAA4DABUACAo1IwwdAA4DABYAAwrcIQYtABgBABQAAgp0I3kXANAAAAAA.Widowghast:BAABNQAECn8dAAITAAgKoBPJugANAgATAAgKoBPJugANAgAAAA==.Willowísp:BAABNQAECn8oAAIoAAkKSBy0BgDaAgAoAAkKSBy0BgDaAgAAAA==.Witerally:BAAANQAECgMIBgAAAA==.',
Wo='Woggers:BAAANQADCgYICwAAAA==.',
Wu='Wujo:BAEANQAECgUIEgAAAA==.',
Xa='Xalthea:BAABNQAECn8pAAQSAAkKaAs0MAC7AQASAAgKSw00MAC7AQAeAAEKwQg2NgAhAAARAAcKGgBDoQATAAAAAA==.Xandapriest:BAAANQADCgYICwABNQAFFAIIBQAYADUQAA==.Xanlock:BAAANQADCgUIBwABNQAECggIIQAhAC0aAA==.',
Xi='Xingyue:BAAANQADCgIIAgABNQAECggIJQAPADoVAA==.',
Xp='Xpddevour:BAABNQAECn8qAAIRAAgKShcBMAAjAgARAAgKShcBMAAjAgAAAA==.',
Xt='Xtena:BAAANQADCgIIAgAAAA==.Xtendron:BAABNQAECn8uAAIMAAkKsB49MgAAAwAMAAkKsB49MgAAAwAAAA==.',
Xu='Xuxo:BAAANQADCgYIBwAAAA==.',
Ya='Yashoda:BAAANQABCggJCAAAAA==.Yawning:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.',
Ye='Yegarmiester:BAAANQAECgUICAAAAA==.Yenti:BAAANQAECgQICQAAAA==.',
Yu='Yuexi:BAAANQADCgYIBgABNQAECggIJQAPADoVAA==.',
['Yâ']='Yâni:BAAANQADCgIIAgAAAA==.',
Za='Zaco:BAABNQAECn8VAAIkAAQK5xqwGAATAQAkAAQK5xqwGAATAQAAAA==.Zamochy:BAAANQAECgUIBQAAAA==.Zap:BAAANQAECgYIBgABNQAECggIGQAcAPcdAA==.',
Ze='Zendàya:BAAANQADCgEIAQAAAA==.Zerality:BAAANQAECgYIDgAAAA==.',
Zh='Zhiso:BAAANQABCgYIBwAAAA==.',
Zi='Ziggie:BAABNQAECn8fAAISAAgKQSXlBgBiAwASAAgKQSXlBgBiAwAAAA==.',
Zo='Zoltan:BAAANQADCggIEQAAAA==.Zookee:BAABNQAECn8eAAIQAAcK2whGKAAuAQAQAAcK2whGKAAuAQAAAA==.',
Zu='Zulizek:BAABNQAECn8dAAIiAAcKGgoPmABHAQAiAAcKGgoPmABHAQAAAA==.',
Zy='Zynister:BAABNQAECn8cAAMGAAkK8xwSEwDxAgAGAAkK8xwSEwDxAgALAAUKzREwgAD2AAAAAA==.',
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
