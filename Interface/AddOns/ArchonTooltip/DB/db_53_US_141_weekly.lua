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

local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Shaman-Elemental','Paladin-Retribution','Rogue-Subtlety','Evoker-Preservation','Druid-Balance','Paladin-Holy','DemonHunter-Devourer','Mage-Arcane',}
local provider = {region='US',realm='Lightbringer',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abahdon:BAAANQAECgYICQAAAA==.',
Ac='Acanarina:BAAANQAECgMIAwAAAA==.Acechapman:BAAANQADCggIDgAAAA==.Achillguy:BAAANQADCgQIBAAAAA==.Aclys:BAAANQAECgYICwAAAA==.',
Ad='Adam:BAAANQAECgYICgAAAA==.Adamrobert:BAAANQADCgUIBQAAAA==.Adamuss:BAAANQAECgcIEAAAAA==.Addiknight:BAAANQAECgQIBQAAAA==.Adonija:BAAANQADCgcIEQAAAA==.Adrenalynn:BAAANQAECgMIAwAAAA==.Adriyel:BAAANQADCggIGwAAAA==.',
Ae='Aegisfang:BAAANQAECgEIAQAAAA==.Aegisrend:BAAANQAECgQIBQAAAA==.Aegrias:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Aellgosa:BAAANQAECgMIAwAAAA==.Aelorias:BAAANQADCgIIAgAAAA==.Aeniras:BAAANQADCgEIAQAAAA==.Aerelyn:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Af='Aflanna:BAAANQAECgUIBQAAAA==.Aforceuser:BAAANQADCgIIAgAAAA==.Aftershock:BAAANQAECgUIBQABNQAECgYICgABAAAAAA==.',
Ag='Aggressive:BAAANQAECgQIBAAAAA==.Agi:BAAANQADCgYIBgAAAA==.Agrezar:BAAANQADCgMIAwAAAA==.',
Ah='Ahlea:BAAANQAECgMIAwAAAA==.Ahnjo:BAAANQADCgMIAwABNQAECgYIDAABAAAAAA==.Ahnkoh:BAAANQADCgYIBgAAAA==.Ahu:BAAANQADCgYICQAAAA==.',
Ai='Ailish:BAAANQADCgEIAQAAAA==.Aindric:BAAANQADCgQIBAAAAA==.',
Ak='Akader:BAAANQAECgIIAgAAAA==.Akkaragos:BAAANQADCggICAAAAA==.Akkarín:BAAANQADCggICAABNQADCggICAABAAAAAA==.Akróasis:BAAANQAECgEIAQAAAA==.',
Al='Alahard:BAAANQADCgcIEQAAAA==.Alariena:BAAANQAECgYICgAAAA==.Alassé:BAAANQAECgIIAgAAAA==.Alcia:BAAANQAECgQIBgAAAA==.Aldrimonk:BAAANQADCgcIBwAAAA==.Aleidari:BAAANQAECgQIBQAAAA==.Alenalee:BAAANQADCggIDgAAAA==.Alexiia:BAAANQADCgIIBAAAAA==.Alfurael:BAAANQAECgEIAQAAAA==.Alisynn:BAAANQAECgQICAAAAA==.Alleriaa:BAAANQADCggIFQAAAA==.Alloryan:BAAANQAECgMIAwAAAA==.Alltiedslam:BAAANQAECgEIAQAAAA==.Almïghty:BAAANQAECgEIAQAAAA==.Alstair:BAAANQAECgQIBwAAAA==.Alythria:BAAANQADCgYIBgAAAA==.Alyvanas:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Alyzei:BAAANQAECgIIAgAAAA==.',
Am='Amaryianul:BAAANQADCgMIAwAAAA==.Ambroesia:BAAANQADCgIIBAAAAA==.Ambulance:BAAANQAECgUICAABNQAECgUICQABAAAAAA==.Amelsea:BAAANQAECgMIBAAAAA==.Amilgaoul:BAAANQADCgQIBAAAAA==.Amirasha:BAAANQADCgYIBQAAAA==.Ammbitious:BAAANQADCgYICAAAAA==.Amá:BAAANQAECgMIAwAAAA==.',
An='Anabanana:BAAANQABCgUIBQAAAA==.Anachron:BAAANQADCgcIEQAAAA==.Anasrastra:BAEANQADCgIIAgABNQAECgIIAgABAAAAAA==.Anastassia:BAAANQADCgYIDgABNQAECgYICAABAAAAAA==.Anderdingus:BAAANQAECgQIBQAAAA==.Andrii:BAAANQABCgMIAQAAAA==.Android:BAABNQAFFIEHAAMCAAUJzQgqAgCDAQACAAUJzQgqAgCDAQADAAEJaQs1CgBMAAAAAA==.Andrà:BAAANQAECgYIBwAAAA==.Anebriated:BAAANQAECgEIAgAAAA==.Angelice:BAAANQADCgUIDAAAAQ==.Angrylock:BAAANQADCgQIBAAAAA==.Animaníac:BAAANQADCgcIEQAAAA==.Animosity:BAAANQADCggIEQAAAA==.Annalorelee:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Annamae:BAAANQADCgYICQAAAA==.Anndal:BAAANQAECgQIBQAAAA==.Anokii:BAAANQADCggIEQAAAA==.',
Ao='Aoeganksta:BAAANQAECgYICgAAAA==.',
Ap='Apnea:BAAANQADCgYIDQAAAA==.',
Aq='Aquadariah:BAAANQAECgQIBgAAAA==.Aquirple:BAAANQAECgIIAgAAAA==.',
Ar='Aranin:BAAANQADCgIIBAAAAA==.Arantes:BAAANQADCgcIEgAAAA==.Arcais:BAAANQAECgIIAgAAAA==.Archibolt:BAAANQADCgIIAgAAAA==.Arcthoradin:BAAANQAECgYICAAAAA==.Arda:BAAANQAECgUIDQAAAA==.Arduanne:BAAANQADCgYICQAAAA==.Aridayä:BAAANQAECgIIAgAAAA==.Arihun:BAAANQADCgYIBgAAAA==.Armeth:BAAANQADCgYIBgAAAA==.Armocida:BAAANQADCgYICgABNQADCgcIDQABAAAAAA==.Arnin:BAAANQADCgUIBQAAAA==.Arnisa:BAAANQADCgYIDgABNQADCgYIEgABAAAAAA==.Arscee:BAAANQAECgEIAQAAAA==.Arthois:BAAANQADCgQIBAAAAA==.Artimuse:BAAANQAECgIIAwAAAA==.Artoo:BAAANQADCgYIBwAAAA==.Artorias:BAAANQADCggIFAAAAA==.Artorus:BAAANQADCgYIDgAAAA==.Arturitifa:BAAANQAECgEIAQAAAA==.',
As='Asahina:BAAANQADCgcIBwAAAA==.Ascendancë:BAAANQAECgUIBgAAAA==.Ashilla:BAAANQAECgEIAQAAAA==.Astartea:BAAANQADCgQIBAAAAA==.Asuriyan:BAAANQADCgYICAAAAA==.Asuryani:BAAANQAECgQICAAAAA==.',
At='Atroxin:BAAANQAECgIIAgAAAA==.',
Au='Auhdia:BAAANQADCggIEwAAAA==.Aumatar:BAAANQAECgUIDAAAAA==.Aumatara:BAAANQADCgMIAwABNQAECgUIDAABAAAAAA==.Auralinn:BAAANQABCgMIAwAAAA==.Auramite:BAAANQAECgYIEAAAAA==.Aurellya:BAAANQAECgEIAQAAAA==.Aurina:BAAANQAECgEIAQAAAA==.Austinpowers:BAAANQADCgYIBgABNQAECgcICgABAAAAAA==.Autümn:BAAANQADCgYIBgAAAA==.Auzua:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Av='Avarim:BAAANQADCggIGAAAAA==.Avirnus:BAAANQADCgUICAAAAA==.Avsapallybro:BAAANQADCgcIEgAAAA==.',
Ax='Axaelle:BAAANQADCgYIBgAAAA==.Axebob:BAAANQADCgIIAgAAAA==.Axesis:BAAANQADCgUIDQAAAA==.Axhell:BAAANQADCgQIBAAAAA==.',
Ay='Ayalei:BAAANQAECgIIBAAAAA==.Ayana:BAAANQADCggIEAAAAA==.',
Az='Azalle:BAAANQAECgYICgAAAQ==.Azarell:BAAANQAECgYICwAAAA==.Azhie:BAAANQAECgYICgAAAA==.Azkara:BAAANQAECgMIBAAAAA==.Azstraza:BAAANQAECgYICwAAAA==.Azurelia:BAAANQAECgQIBQAAAA==.Azyrel:BAAANQADCgIIAgAAAA==.',
['Aî']='Aîma:BAAANQAECgQIBwAAAA==.',
Ba='Babbafett:BAAANQAECggIAQAAAA==.Baktria:BAAANQADCgQIBAABNQADCgcIEgABAAAAAA==.Ballofdoom:BAAANQAECgEIAQAAAA==.Bamboosifu:BAAANQADCgYICgAAAA==.Baobunn:BAAANQADCgIIBAAAAA==.Bazzard:BAAANQADCgcIEwAAAA==.',
Bb='Bbellaa:BAAANQADCgMIAwAAAA==.',
Be='Bearhy:BAAANQADCgUIDgAAAA==.Bebb:BAAANQAECgIIAgAAAA==.Beefychief:BAAANQAECgEIAQAAAA==.Beko:BAAANQAECgYICwAAAA==.Belenar:BAAANQADCggIBgAAAA==.Berthà:BAAANQADCgYIBgAAAA==.',
Bh='Bhonk:BAAANQADCgUIBwAAAA==.Bhrams:BAAANQAECgQIBgAAAA==.',
Bi='Bibby:BAAANQAECgQIBAABNQADCgYIBgABAAAAAA==.Bigbahdwolff:BAAANQAECgIIAwAAAA==.Bigbootyjudy:BAAANQADCgQIBAAAAA==.Bighugz:BAEANQADCggIFAAAAA==.Bigjuici:BAAANQAECgQIBgAAAA==.Bigunc:BAAANQAFFAEIAwAAAA==.Billmunny:BAAANQADCgcIEgAAAA==.Bismyth:BAAANQAECgEIAQAAAA==.Bitterblue:BAAANQAECgQICAAAAA==.',
Bl='Blasphumy:BAAANQADCgYIDQAAAA==.Blaybe:BAAANQABCgIIAgAAAA==.Bldk:BAAANQAECgEIAQABNQADCgEIAQABAAAAAA==.Bleexx:BAAANQAECgYICgAAAA==.Blendtec:BAAANQADCgQIBAAAAA==.Blessanay:BAAANQADCggIEwAAAA==.Blightstalkr:BAAANQADCgcIDAAAAA==.Bludnite:BAAANQADCgYIBgABNQAECgYIBwABAAAAAA==.Blueeyestare:BAAANQAECgYIDAAAAA==.Bluefoxy:BAAANQADCgUICgAAAA==.Blueshock:BAAANQAECggIBAAAAA==.Bluesy:BAAANQAECgYICgAAAA==.Bluudflagg:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Blüepill:BAAANQAECgMIAwABNQAECggIEgABAAAAAA==.',
Bo='Bodåcious:BAAANQAECgYICQAAAA==.Bokblade:BAAANQAECgMIBAAAAA==.Bonezardo:BAAANQAECgIIAwAAAA==.Boomzel:BAAANQADCgYIBgAAAA==.Boozkin:BAAANQADCgQIBgAAAA==.Bosk:BAAANQADCgYIBwAAAA==.Bowknight:BAAANQADCgYICQAAAA==.Bowserfist:BAAANQADCgIIAgAAAA==.',
Br='Branze:BAAANQADCgMIAwAAAA==.Brauer:BAAANQAECgEIAQAAAA==.Brecht:BAAANQAECgYICgAAAA==.Breean:BAAANQADCgcIEQAAAA==.Brendia:BAAANQADCgYICQAAAA==.Breylla:BAAANQAECgUIBwAAAA==.Bridge:BAAANQADCgYIBgAAAA==.Brinze:BAAANQADCgYICwAAAA==.Brisquik:BAAANQADCgcIGAAAAA==.Brokenheals:BAAANQAECgYICQAAAA==.Brokenspirit:BAAANQAECgIIAwABNQAECgYICQABAAAAAA==.Bromax:BAAANQAECggIEwAAAA==.Bromeatigans:BAAANQAECgQIBQAAAA==.Broncobill:BAAANQADCgIIAgABNQADCgcIEgABAAAAAA==.Bronzebeards:BAAANQABCgMIAwAAAA==.Bronzeblade:BAAANQADCgEIAQAAAA==.Brosef:BAAANQAECgEIAQAAAA==.Brunosteiner:BAAANQADCgUIBQAAAA==.Brëwdaddy:BAAANQAECgEIAQAAAA==.',
Bu='Bubbleurface:BAAANQAECgEIAQAAAA==.Budmax:BAAANQADCggICAAAAA==.Buggy:BAAANQADCgQIBAAAAA==.Bulgogï:BAAANQAECgQIBAAAAA==.Bulldin:BAAANQADCgYIBgAAAA==.Bunduk:BAAANQAECgEIAQAAAA==.Bunnymuffin:BAAANQADCgEIAQAAAA==.Burnmyeyes:BAAANQADCgQIBAAAAA==.Burrmutt:BAAANQADCgEIAQAAAA==.Butterboi:BAAANQAECgEIAQAAAA==.Buxal:BAAANQAECgUIBQAAAA==.Buzzjägaren:BAAANQAECgIIAgAAAA==.',
Bw='Bwe:BAAANQADCgYICAABNQADCgYIDAABAAAAAA==.',
['Bä']='Bällador:BAAANQAECgIIAgAAAA==.',
['Bë']='Bëlen:BAAANQADCggIDgAAAA==.',
Ca='Cailiand:BAAANQADCgYIBgAAAA==.Cailo:BAAANQADCgcICwAAAA==.Caitrionna:BAAANQADCgUICQABNQADCgcIDwABAAAAAA==.Calarraa:BAAANQADCgQIBAAAAA==.Caliasha:BAAANQAECgQICAAAAA==.Calithdrel:BAAANQADCgcIEgAAAA==.Calivoker:BAAANQADCgQIBwABNQADCgcIEgABAAAAAA==.Callanan:BAAANQAECgMIBQAAAA==.Calumn:BAAANQADCggIDgAAAA==.Calystaa:BAAANQAECgEIAQAAAA==.Camotwo:BAAANQAECgQICAAAAA==.Cardio:BAAANQABCgQIBAAAAA==.Caro:BAAANQAECgMIAwAAAA==.Casafrass:BAAANQAFFAEIAQAAAA==.Cascc:BAAANQAECgEIAQAAAA==.Caspop:BAAANQAECgMIBAAAAA==.Castalia:BAAANQADCgYICgAAAA==.Catcatchme:BAEANQAECgYICwAAAA==.Cathalla:BAAANQAECgMIAwAAAA==.Catmaxxing:BAAANQADCgcIBwAAAA==.Cava:BAAANQADCgcIBwAAAA==.Caïtïr:BAAANQADCgcIBgAAAA==.',
Ce='Celebrant:BAAANQAECgQIBQAAAA==.Celendiel:BAAANQADCggIDQAAAA==.Celicus:BAAANQAECgIIAgAAAA==.Celinil:BAAANQADCgQIBAAAAA==.Cenadyen:BAAANQADCgUICgAAAA==.Cerror:BAAANQADCgYIDQAAAA==.Cervantez:BAAANQAECgYICwAAAA==.',
Ch='Chahan:BAAANQADCggICAAAAA==.Chambers:BAAANQADCgYIBgAAAA==.Changeforms:BAAANQAECgEIAQAAAA==.Chaosmops:BAAANQADCgYICgAAAA==.Cheekks:BAAANQADCgcIEgAAAA==.Cheestick:BAAANQAECgQIBQAAAA==.Cheif:BAAANQAECgQIBgAAAA==.Cherfslight:BAAANQADCgYIBwAAAA==.Cherishlove:BAAANQADCgYICgAAAA==.Chezmerelde:BAAANQADCggIFgAAAA==.Chibidrez:BAAANQADCgIIAgAAAA==.Choekame:BAAANQADCgYIBwAAAA==.Choopy:BAAANQAECgEIAQAAAA==.Chowito:BAAANQAECgQIBQAAAA==.Chromedout:BAAANQAECgMIBgAAAA==.Chromme:BAAANQADCgcIGAAAAA==.Chuku:BAAANQADCgYIDgAAAA==.',
Ci='Cicii:BAAANQAECgQIBAAAAA==.Cillia:BAAANQADCgUIBQAAAA==.Cinnabunbun:BAAANQADCggIFAAAAA==.Ciradae:BAAANQADCgQIBAAAAA==.Cirannis:BAAANQADCgQIBgAAAA==.',
Cl='Claieth:BAAANQADCgYIBgAAAA==.Cller:BAAANQADCgEIAQABNQADCgYIDAABAAAAAA==.',
Co='Coal:BAAANQAECgMIBAAAAA==.Cocobe:BAAANQADCggIEAAAAA==.Coffeequeene:BAAANQABCgIIAwAAAA==.Coffeesilk:BAAANQADCgEIAQAAAA==.Coily:BAAANQADCgMIAwABNQADCgcIDgABAAAAAA==.Coni:BAAANQAECgQIBgAAAA==.Conqweefador:BAAANQADCgUIBwAAAA==.Contriclu:BAAANQADCgMIAwAAAA==.Copypasta:BAAANQAECgcIDQAAAQ==.Corghat:BAAANQAECgQIBQAAAA==.Cornfucius:BAAANQAECgcIDgAAAA==.Cornoodle:BAAANQADCgUIBQAAAA==.Corvinä:BAAANQADCggIDwABNQAECgIIAgABAAAAAA==.Courad:BAAANQAECgUIBgAAAA==.',
Cr='Crackalackn:BAAANQADCgIIAgAAAA==.Crackerjill:BAEANQAECgQIBgAAAA==.Craftysoul:BAAANQADCgEIAQAAAA==.Crazydwarf:BAAANQAECgIIAgAAAA==.Crescendø:BAAANQADCgYICgAAAA==.Crinkle:BAAANQAECgYICgAAAA==.Critterx:BAAANQAECgQICAAAAA==.Crowofwar:BAAANQADCgQIBQAAAA==.Crysilisk:BAAANQAECgQICAAAAA==.Crystalnight:BAAANQAECgEIAQAAAA==.',
Cu='Currants:BAAANQADCggIDAAAAA==.',
Cy='Cyborglol:BAAANQADCggICAAAAA==.Cygani:BAAANQAECgQIBwAAAA==.Cynaesthesia:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Cynedrasong:BAAANQAECgQICAAAAA==.Cynwin:BAAANQAECgMIAwAAAA==.',
['Cà']='Càmo:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
['Cä']='Cäkë:BAAANQAECgIIAgAAAA==.',
['Cè']='Cèrebor:BAAANQADCgIIAgAAAA==.',
['Cø']='Cørvus:BAAANQAECgEIAQAAAA==.',
Da='Daesi:BAAANQAECgYICgAAAA==.Dagnorath:BAAANQAECgQIBQAAAA==.Daisydark:BAAANQADCgYICgAAAA==.Daleteme:BAAANQAECgcIBwAAAA==.Dalika:BAAANQAECgQICgAAAA==.Dalscars:BAAANQAECgYICQAAAA==.Dancampby:BAAANQADCgMIBQAAAA==.Dankshots:BAAANQAECggIEwAAAA==.Daphnedowns:BAAANQADCgIIAgAAAA==.Darann:BAAANQAECgQIBgAAAA==.Darkaeris:BAAANQADCgcIDQAAAA==.Darknemisis:BAAANQADCgEIAQAAAA==.Datash:BAAANQAECgIIAgAAAA==.Davyynccii:BAAANQAECgMIBAAAAA==.Dawheight:BAAANQADCgMIAwABNQAECgYICwABAAAAAA==.Daybringer:BAAANQADCgYICgAAAA==.Daïsy:BAAANQAECgQICAAAAA==.',
De='Deadcrag:BAAANQAECgQICAAAAA==.Deadtawko:BAAANQAECgEIAQAAAA==.Deardra:BAAANQADCggIDwAAAA==.Deatherage:BAAANQAECgEIAQAAAA==.Deathjans:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Deathpenance:BAAANQADCgYICQAAAA==.Deathrazer:BAAANQADCggIFAAAAA==.Deathsdemon:BAAANQADCgUICQAAAA==.Deathseeker:BAABNQAECoEWAAMEAAgJ5BsWEQCXAgAEAAgJ5BsWEQCXAgAFAAEJcxMtMAA+AAAAAA==.Deathwolfs:BAAANQADCgUIBAAAAA==.Decoyfamily:BAAANQADCggIFQABNQAECgYIDAABAAAAAA==.Dedgathering:BAAANQADCgYICQAAAA==.Deetours:BAAANQAECgQICwAAAA==.Deidamia:BAAANQADCgMIAwAAAA==.Deirdra:BAAANQADCgcIBwAAAA==.Delat:BAAANQAECgMIBAAAAA==.Delsteve:BAAANQABCgIIAQAAAA==.Delyssuh:BAAANQAECgQICAAAAA==.Demyred:BAAANQAECgMIAwAAAA==.Denddar:BAAANQADCgYIDgAAAA==.Destinyeyes:BAAANQAECgQIBgAAAA==.Deuteros:BAAANQADCgQIBAAAAA==.Devianthunt:BAAANQAECgUICQAAAA==.',
Df='Dfg:BAAANQAECgYICwAAAA==.',
Di='Diddledeebum:BAAANQAECgUIBwAAAA==.Dinkysoleil:BAAANQADCgYICwAAAA==.Dirtyfist:BAAANQAECggIBgAAAA==.Disbeliever:BAAANQAECgQIBQAAAA==.Dislustic:BAAANQAECgQIBwABNQAECgYICQABAAAAAA==.',
Dk='Dkawesomness:BAAANQADCgcIEQAAAA==.',
Dm='Dmc:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Do='Dokiron:BAAANQADCgUICAAAAA==.Domeki:BAAANQADCggIDAAAAA==.Domimommy:BAAANQAECgQIBQAAAA==.Dontjudgeme:BAAANQAECgYIBgAAAA==.Doomblossom:BAAANQADCgQIBAAAAA==.Doromarius:BAAANQADCgQIBwAAAA==.Dozèr:BAAANQAECgYICgABNQAECgYICwABAAAAAA==.',
Dp='Dpshunter:BAABNQAECoEXAAQCAAkJ5SGoAwBhAwACAAkJ5SGoAwBhAwADAAEJaSC9iABVAAAGAAEJ0AcyCQA7AAAAAA==.',
Dr='Dracyr:BAAANQABCgIIAgAAAA==.Draevan:BAAANQAECgUICgAAAA==.Draglan:BAAANQABCgUIBQAAAA==.Dragonslime:BAAANQADCgcIEgAAAA==.Drakkthar:BAAANQADCgMIBAAAAA==.Drakloak:BAAANQADCgcIEgAAAA==.Dranae:BAAANQADCgcIBwAAAA==.Dravion:BAAANQAECgYICAAAAA==.Drazlock:BAAANQADCgIIAgAAAA==.Drcoup:BAAANQADCggIDwAAAA==.Drevin:BAAANQAECgMIBAAAAA==.Drezriel:BAAANQAECgIIAgAAAA==.Droodzilla:BAAANQADCgYICQAAAA==.Drukket:BAAANQADCgMIAwAAAA==.Dryadius:BAAANQAECgQIBgAAAA==.Dràgón:BAAANQADCggIFAAAAA==.',
Du='Dualîty:BAAANQADCggICAABNQAECggIEAABAAAAAA==.Duana:BAAANQAECgQIBgAAAA==.Ducksaas:BAAANQADCgYIBgAAAA==.',
Dv='Dvlishadhira:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
Dw='Dwagonbwulgi:BAAANQAECgIIAgAAAA==.',
Dy='Dycrons:BAAANQAECgcIDQAAAA==.Dynaohs:BAAANQADCgYICgAAAA==.',
Eb='Ebenzer:BAAANQAECggIDgAAAA==.Ebenzervoid:BAAANQADCgIIAgABNQAECggIDgABAAAAAA==.Ebonomix:BAAANQADCgcIBwAAAA==.Ebön:BAAANQADCgEIAQABNQADCgcIBwABAAAAAA==.',
Ec='Eclipsè:BAAANQADCgUIAwAAAA==.',
Ei='Eibon:BAAANQADCgQIBwAAAA==.Eirä:BAAANQAECgMIAwAAAA==.Eithriand:BAAANQADCgYICwAAAA==.Eitrr:BAAANQAECgEIAQAAAA==.',
El='Elchræl:BAAANQADCgQIAwAAAA==.Eldadog:BAAANQADCgMIAwAAAA==.Eldenstone:BAAANQADCgYIBgAAAA==.Electronik:BAAANQAECgEIAQABNQAECgYIEAABAAAAAA==.Eliesa:BAAANQAECgMIBAABNQAECgYICwABAAAAAA==.Ellvira:BAAANQAECgMIBAAAAA==.Ellyriax:BAAANQAECgQIBAAAAA==.Elsbeth:BAAANQAECgMIAwAAAA==.Eltex:BAAANQADCgcIEQAAAA==.Eluveitie:BAAANQADCggICAAAAA==.Elv:BAAANQAECgQICAAAAA==.Elwisp:BAAANQADCgYIBgAAAA==.',
En='Endlessmoon:BAAANQADCgcIFAAAAA==.Enflexi:BAAANQAECgQIBwAAAA==.Engrave:BAAANQADCgYICgAAAA==.Enrox:BAAANQABCgEIAQAAAA==.Entro:BAAANQAECgUIBwAAAA==.',
Eo='Eorana:BAAANQAECgcIDwAAAA==.',
Ep='Ephoriah:BAAANQAECgQICAAAAA==.',
Er='Ericho:BAAANQAECgQIBwAAAA==.Erris:BAAANQAECgMIAwAAAA==.Erunak:BAAANQAECgYICAAAAA==.',
Es='Esmiriel:BAAANQADCgUIBQAAAA==.Estasa:BAAANQAECgEIAQAAAA==.Esuna:BAAANQADCgUIBQAAAA==.',
Et='Etgamer:BAAANQAECgMIAwAAAA==.Ettepriest:BAAANQAECgIIAgAAAA==.Ettyn:BAAANQAECgQIBQAAAA==.',
Ev='Everymanimal:BAAANQAECgMIAwAAAA==.Evolex:BAAANQAECgQIBgAAAA==.Evollana:BAAANQAECgcIEwAAAA==.',
Ez='Ezith:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
['Eí']='Eín:BAAANQADCgYIDAAAAA==.',
['Eñ']='Eñzytë:BAAANQADCgMIAwABNQAECgEIAgABAAAAAA==.',
Fa='Faalana:BAAANQADCggIFAAAAA==.Failbones:BAAANQAECggIEgAAAA==.Faks:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Falsecrack:BAAANQAECgIIAgAAAA==.Farand:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Farnox:BAAANQAECgEIAQAAAA==.Fatfurry:BAAANQAECgUIBgAAAA==.Faustirian:BAAANQAECgEIAQAAAA==.Fay:BAAANQAECgEIAQAAAA==.',
Fe='Fearsmonk:BAAANQADCgQIBAAAAA==.Felgrihm:BAEANQADCgUIDgABNQADCggIEwABAAAAAA==.Felmeup:BAAANQADCggIFAAAAA==.Feoranne:BAAANQAECgIIAgAAAA==.Feralshaman:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Feren:BAAANQAECgQIBQAAAA==.Ferrek:BAAANQABCgIIAwAAAA==.',
Fh='Fhurian:BAEANQADCgcIDAABNQADCggIEwABAAAAAA==.',
Fi='Fi:BAAANQAECgIIAgAAAA==.Fiasco:BAAANQADCggIDgAAAA==.Fifthwheel:BAAANQADCgMIAwAAAA==.Firo:BAAANQADCgMIAwAAAA==.Fisst:BAAANQAECgEIAQAAAA==.Fistypurk:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Fivecentwarr:BAAANQAECgQIBQAAAA==.',
Fl='Flabby:BAAANQAECggIDwAAAA==.Flandis:BAAANQADCgIIAgAAAA==.Flashback:BAAANQADCggICAAAAA==.Flet:BAAANQADCgIIAgAAAA==.Fleurt:BAAANQAECgMIBAAAAA==.Flexxi:BAAANQABCgQIBAAAAA==.Flighent:BAAANQADCgQIBQAAAA==.Floorgodx:BAAANQAECgUIBwAAAA==.Flore:BAAANQAECgQIBAAAAA==.Floriinn:BAAANQADCggICgAAAA==.Flourish:BAAANQAECgYICgAAAA==.Flowblue:BAAANQADCgcIBwAAAA==.Flufflles:BAAANQADCgQIBAAAAA==.',
Fo='Fontanä:BAAANQADCggIFAAAAA==.Food:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Forioss:BAAANQAECgUIBgAAAA==.Forlyfe:BAAANQAECgEIAQAAAA==.Fortyhands:BAAANQAECgMIAwAAAA==.Foxanar:BAAANQAECgIIAgAAAA==.Foxdunter:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.',
Fr='Fractures:BAAANQADCggIDQAAAA==.Frane:BAAANQAECgUIBgAAAA==.Freakazoíd:BAAANQABCgIIAgAAAA==.Freakly:BAAANQADCgcIEgAAAA==.Freesamples:BAAANQADCgIIAgAAAA==.',
Fu='Fubarius:BAAANQADCgMIAwAAAA==.Fullplatefox:BAAANQADCgUIDgAAAA==.Funklelock:BAAANQAECgcIDQAAAA==.Furo:BAAANQADCgIIBAAAAA==.Fuzzytek:BAAANQADCgYIDwAAAA==.',
Fw='Fweezem:BAAANQABCgQIBgAAAA==.',
Fy='Fyggdrasil:BAAANQADCgUIBAAAAA==.',
['Fé']='Félboots:BAAANQADCgYIDgAAAA==.',
Ga='Gadgetwrench:BAAANQADCgYICwAAAA==.Galenas:BAAANQADCgEIAQAAAA==.Galeo:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Gales:BAAANQAECgMIAwAAAA==.Gallagar:BAAANQAECgMIAwAAAA==.Gallo:BAAANQAECgEIAQAAAA==.Galvek:BAAANQADCgYIBgAAAA==.Gandgof:BAEANQADCgQIBAABNQAECgIIAgABAAAAAA==.Garfish:BAAANQADCggIFQAAAA==.Garrics:BAAANQAECgIIAgAAAA==.Garyndorni:BAAANQAECgEIAQAAAA==.Gathaf:BAAANQAECgQIBQAAAA==.',
Ge='Gealtachta:BAAANQAECgQIBQAAAA==.Gebus:BAAANQADCgUIDgAAAA==.Geeby:BAAANQAECgMIAwAAAA==.Gelebros:BAAANQAECgEIAQAAAA==.Gematrîa:BAAANQAECggIEAAAAA==.Genovevaa:BAAANQADCggICwAAAA==.Geoffliction:BAAANQADCgYIBwAAAA==.Geöde:BAAANQAECgMIAwAAAA==.',
Gh='Ghamma:BAAANQAECgQIBAAAAA==.Ghostops:BAAANQAECgcICwAAAQ==.',
Gi='Gibberish:BAAANQAECgYICwAAAA==.Gildàrts:BAAANQADCgUIBQAAAA==.Gilgamush:BAAANQADCggIDQAAAA==.Gimthal:BAAANQAECgIIAgAAAA==.Ginevra:BAAANQADCgUICQAAAA==.',
Gl='Glacierstorm:BAAANQADCgIIBAAAAA==.Glaivewaifu:BAAANQADCgUICQAAAA==.Glenvulin:BAAANQADCgYIBgAAAA==.Glorymetcalf:BAAANQADCgUIDgAAAA==.',
Go='Gofsham:BAEANQAECgIIAgAAAA==.Golandrith:BAAANQADCgIIBAAAAQ==.Goobertork:BAAANQADCggIDwAAAA==.Goombo:BAAANQAECgUIBQAAAA==.Gordonramsme:BAAANQADCggIFAAAAA==.Gorillasdk:BAAANQAECgIIAgAAAA==.Gornok:BAAANQADCgYIBwAAAA==.Gothgf:BAAANQAECgEIAQAAAA==.Goturcakes:BAAANQADCgYICgAAAA==.',
Gr='Grayfawks:BAAANQAECgIIAgAAAA==.Graywulf:BAAANQADCggIGQAAAA==.Grazzyazz:BAAANQAECgEIAQAAAA==.Greensocks:BAAANQAECgQIBgAAAA==.Greenwarrior:BAAANQADCgEIAQABNQAECgcIBwABAAAAAA==.Grekar:BAAANQADCgQIBAAAAA==.Greynutz:BAAANQADCggIAgAAAA==.Grillcheese:BAAANQAECgQIBAAAAA==.Grippisocks:BAAANQAECgYIDQABNQADCggICAABAAAAAA==.Gryffgunner:BAAANQAECgQIBQAAAA==.Græl:BAAANQADCgYICgAAAA==.',
Gu='Guarok:BAAANQAECgQIBQAAAA==.Gugizimo:BAAANQAECgQIBgAAAA==.Guvante:BAAANQADCgYIBgAAAA==.',
Gw='Gwenavare:BAAANQAECgUICQAAAA==.',
Ha='Habde:BAAANQADCgIIAgABNQADCggICwABAAAAAA==.Haise:BAAANQADCgcIFgAAAA==.Handpump:BAAANQADCgUIDAAAAA==.Hans:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Happyhunting:BAAANQADCggIDQAAAA==.Haranasty:BAAANQAECgQIBQAAAA==.Hardasarock:BAAANQAECgUICwAAAA==.Harigise:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Harrypooty:BAAANQABCgMIAwAAAA==.Harrysnoot:BAAANQAECgIIAgAAAA==.Hastalÿk:BAAANQADCgcIBwAAAA==.Haugll:BAAANQABCgQIBgAAAA==.Havsham:BAAANQAECgYICQAAAA==.Hawa:BAAANQADCgYIDAAAAA==.Hawgcranked:BAAANQADCgYIBgAAAA==.Haydmage:BAAANQADCgYICgAAAA==.',
He='Heartily:BAAANQAECgEIAQAAAA==.Heddurr:BAAANQAECgUICAAAAA==.Helruner:BAAANQADCgcICQAAAA==.Heltrskelter:BAAANQAECgQIBAAAAA==.Henbob:BAAANQADCgMIBAAAAA==.Hercdh:BAAANQABCgUIBQAAAA==.Hercion:BAAANQABCgIIAgABNQADCgcIDQABAAAAAA==.Hercmage:BAAANQADCgcIDQAAAA==.Hevelina:BAAANQADCggIFgAAAA==.Hezekiahh:BAAANQADCgcICgAAAA==.',
Hi='Hieroglyphix:BAAANQADCgEIAQAAAA==.Highbeams:BAAANQADCgYICAAAAA==.',
Ho='Holyinnocent:BAAANQADCgYICQAAAA==.Honeyrevolvr:BAAANQADCgYICgAAAA==.Hoobz:BAAANQAECgMIAwAAAA==.Hoser:BAAANQADCgYICQAAAA==.Hotbunzz:BAAANQADCgIIAgAAAA==.',
Hv='Hvylights:BAAANQAECgcIDQAAAA==.',
Hy='Hydronimbus:BAAANQADCgMIAwAAAA==.Hypershock:BAAANQAECgYIDgAAAA==.',
['Hó']='Hómey:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Hómiee:BAAANQAECgQICAAAAA==.',
Ic='Iccecycle:BAAANQADCgUIBQAAAA==.Icehopper:BAAANQADCgEIAQAAAA==.',
Id='Idksmthindum:BAAANQAECgYICgAAAA==.',
Ih='Ihavelust:BAAANQAECgYICgAAAA==.',
Ik='Ikunoxi:BAAANQAECgUICAAAAA==.',
Im='Immortalnite:BAAANQAECgYIBwAAAA==.',
In='Incubus:BAAANQABCgIIAwAAAA==.Ingvar:BAAANQABCgMIBQAAAA==.Innerfury:BAAANQADCgEIAQABNQADCgcIEgABAAAAAA==.Innertempler:BAAANQADCgIIAgABNQADCgcIEgABAAAAAA==.Innerthunder:BAAANQADCgYIBgABNQADCgcIEgABAAAAAA==.Insufferable:BAAANQADCgcIDAAAAA==.',
Ir='Ironboar:BAAANQADCgUICAAAAA==.Ironlobster:BAAANQADCgUIBQAAAA==.',
Is='Ishymaell:BAAANQADCggIDAAAAA==.',
Iv='Ivanatrump:BAAANQADCgYIDAAAAA==.',
Iz='Izsún:BAAANQADCgUIDgAAAA==.',
Ja='Jadasmith:BAAANQABCgQIBAAAAA==.Jaena:BAAANQADCgUICAAAAA==.Jaggler:BAAANQAECgUIBQAAAA==.Jainá:BAAANQADCgYIBgAAAA==.Jakew:BAAANQAECgYICAAAAA==.Janceynniela:BAAANQAECgEIAQAAAA==.Janspally:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.Jashe:BAAANQAECgEIAQAAAA==.Jassaene:BAAANQABCgIIAgAAAA==.Jatzartok:BAAANQAECgIIAgAAAA==.Javarielle:BAAANQAECgYIDQAAAA==.Javelina:BAAANQAECgMIAwAAAA==.Jaydemon:BAAANQAECgIIBAAAAA==.Jayrock:BAAANQAECgQIBAAAAA==.',
Jb='Jblack:BAAANQADCgcIDQAAAA==.',
Je='Jeandárc:BAAANQADCgQIBAAAAA==.Jemm:BAAANQADCgcIDQAAAA==.Jeritza:BAAANQAECgEIAQAAAA==.Jeruko:BAACNQAFFIEEAAIHAAMJ9x5BAgAtAQAHAAMJ9x5BAgAtAQA1AAQKgRcAAgcACQngJX4AAO0DAAcACQngJX4AAO0DAAAA.',
Jh='Jhalori:BAAANQADCgYIBgAAAA==.',
Ji='Jihi:BAAANQAECgEIAQAAAA==.Jiminycrick:BAAANQAECgMIBQAAAA==.',
Jo='Johnwiccan:BAAANQADCggICAAAAA==.Jonezi:BAAANQAECgUICgAAAA==.Jothaie:BAAANQADCgYIDgAAAA==.',
Jr='Jragonknight:BAAANQAECgEIAQAAAA==.',
Ju='Judged:BAAANQAECgQIBAAAAA==.Judgemo:BAAANQAECgQICAAAAA==.Judgytek:BAAANQADCgIIAgABNQADCgYIDwABAAAAAA==.Juggernasty:BAAANQADCgUICQAAAA==.Jumpnjak:BAAANQAECggIBgAAAA==.Jumpy:BAAANQAECgMIAwAAAA==.Justdax:BAAANQAECgEIAQAAAA==.Justthetips:BAAANQADCgYIDgAAAA==.',
['Jø']='Jønø:BAAANQAECgYICAAAAA==.',
Ka='Kaast:BAAANQAECgUICQAAAA==.Kaddee:BAAANQADCggIEQABNQAECgYICwABAAAAAA==.Kaelin:BAAANQADCgUIBQAAAA==.Kaemra:BAAANQAECgQIBQAAAA==.Kahto:BAAANQADCgYIDQAAAA==.Kaialandre:BAAANQAECgcIDQAAAA==.Kajri:BAAANQADCgQIBAAAAA==.Kalenian:BAAANQAECgYICQAAAA==.Kalldin:BAAANQAECgMIAwAAAA==.Kalnoth:BAAANQABCgYIBgAAAA==.Kalubew:BAAANQAECgUIBwABNQAECgYICQABAAAAAA==.Kalî:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Kalîente:BAAANQAECgUICAAAAA==.Kaprah:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Karal:BAAANQADCggIEAAAAA==.Karinfromhr:BAAANQABCgIIAgAAAA==.Karrowin:BAAANQADCgUIBQAAAA==.Karzon:BAAANQADCggIFAAAAA==.Katamoria:BAAANQAECgEIAQAAAA==.Katarìe:BAAANQADCggIFgAAAA==.Katsara:BAAANQAECgQIBQAAAA==.Kavaax:BAAANQAECgYICgAAAA==.Kaydence:BAAANQAECgQIBQAAAA==.Kaydiah:BAAANQAECgEIAQAAAA==.Kaylinne:BAAANQADCgUIBQAAAA==.Kayllia:BAAANQADCgYIBwAAAA==.Kayrâe:BAAANQADCggICAABNQAECggIDwABAAAAAA==.',
Ke='Keenaxe:BAAANQAECgQIBQAAAA==.Keggiesmalls:BAAANQADCggIDAABNQAECggIEgABAAAAAA==.Keldorn:BAAANQAECgYIBgAAAA==.Kelthear:BAAANQAECgQIBgAAAA==.Kelína:BAAANQAECgQIBAAAAA==.Kenrato:BAAANQAECgMIAwAAAA==.Kensen:BAAANQADCgYIDAAAAA==.Kerianassa:BAAANQADCgUIBAAAAA==.',
Kh='Khalais:BAAANQADCgcIBwAAAA==.Kharalla:BAAANQAECgIIAgAAAA==.Khorhil:BAAANQADCggIDgAAAA==.',
Ki='Kiki:BAAANQAECgMIAwAAAA==.Kilhara:BAAANQAECgQIBQAAAA==.Killerthighs:BAAANQADCgIIAgAAAA==.Kinadin:BAAANQADCgQIBAAAAA==.Kinegos:BAAANQAECgYIBwAAAA==.Kirint:BAAANQADCgEIAQABNQAECgYICwABAAAAAA==.',
Kn='Knarlee:BAAANQAECgIIAgAAAA==.Knob:BAAANQAECgUICgAAAA==.Knockd:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Knockz:BAAANQAECgQIBgAAAA==.',
Ko='Kobask:BAAANQADCgUIBwAAAA==.Kobisk:BAAANQADCggICAAAAA==.Konvicktion:BAAANQADCggIDQAAAA==.',
Kr='Kratoast:BAAANQADCgYICQAAAA==.Kraytous:BAAANQAECgYIDAAAAA==.Kregon:BAAANQADCggIGAAAAA==.Kretolo:BAAANQAECgIIAgAAAA==.Kribage:BAAANQADCggIEQAAAA==.Krozard:BAAANQAECgQIBgAAAA==.Kríelle:BAAANQAECgYIDQAAAA==.',
Ku='Kuinshie:BAAANQADCggIEgABNQAECgEIAQABAAAAAA==.',
Ky='Kyeras:BAAANQADCgYIBgAAAA==.Kyr:BAAANQADCgYIEQAAAA==.Kyra:BAAANQADCgYIDwAAAA==.Kyriophra:BAAANQADCgUIBQAAAA==.Kyriélle:BAAANQAECgQIBQAAAA==.Kyrral:BAAANQADCgYIBgAAAA==.',
['Kà']='Kài:BAAANQADCgMIAwAAAA==.',
La='Labowski:BAAANQADCgUIBQAAAA==.Laeara:BAAANQAECgYICAABNQADCgUICAABAAAAAA==.Lamantee:BAAANQABCgQICAAAAA==.Lanaera:BAAANQADCgUIBgAAAA==.Laneer:BAAANQAECgQIBAAAAA==.Lannivath:BAAANQAECgcIBwAAAA==.Larah:BAAANQADCgQIBgAAAA==.Lavabêard:BAAANQAECgEIAQAAAA==.Laviinia:BAAANQABCgQIBgAAAA==.Lawkie:BAAANQADCgYIBgABNQADCgUICAABAAAAAA==.Lawnart:BAAANQADCgQIBAAAAA==.Laxus:BAAANQADCggIEQAAAA==.Lazm:BAAANQAECgcICwAAAA==.',
Le='Leliot:BAAANQAECgIIBAAAAA==.Leona:BAAANQAECggICAAAAA==.Lethea:BAAANQADCgYIBgABNQAECggIDgABAAAAAA==.',
Li='Liamdir:BAAANQADCgEIAQAAAA==.Licestr:BAAANQAECgMIAwAAAA==.Lichmyshot:BAAANQAECgEIAQAAAA==.Lightcleave:BAAANQADCgIIAgAAAA==.Lightdmg:BAAANQADCgcIBwAAAA==.Lightemperos:BAAANQABCgQIAgAAAA==.Lightguy:BAAANQAECgQIBgAAAA==.Lightma:BAAANQAECgQICAABNQAECgQIBwABAAAAAA==.Lilaitria:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Lilgaybear:BAAANQADCgIIAgABNQAECgcIEQABAAAAAA==.Liliybug:BAAANQADCggIEQAAAA==.Lilpandibr:BAAANQADCggIEwAAAA==.Lilyroses:BAAANQADCgcIEgAAAA==.Limitless:BAAANQABCgQIBgAAAA==.Linash:BAAANQADCgYIDAAAAA==.Lindrysong:BAAANQADCgMIBAABNQAECgQICAABAAAAAA==.Linsin:BAAANQADCggIFgAAAA==.Littlesun:BAAANQADCgQIBAAAAA==.Lizardlick:BAAANQAECgEIAQAAAA==.',
Ll='Llamaknight:BAAANQAECgYIDQAAAA==.',
Lo='Lockdark:BAAANQADCgEIAQAAAA==.Lockedout:BAAANQADCggICAAAAA==.Lockjom:BAAANQAECgQIBQAAAA==.Locutie:BAAANQADCgcIEgAAAA==.Lokrah:BAAANQADCgYIBgAAAA==.Lost:BAAANQAECgIIAgAAAA==.Lostson:BAAANQADCgQIBAAAAA==.Loveliness:BAAANQABCgQIBAAAAA==.Loviatar:BAAANQAECgQIBgAAAA==.Loviro:BAAANQAECgQIBgAAAA==.',
Lu='Lubetech:BAAANQADCgcIBwABNQADCgcIBwABAAAAAA==.Lucinus:BAAANQADCggIDgAAAA==.Lunahuntress:BAAANQADCgYIBgAAAA==.Lusty:BAAANQADCgUICQAAAA==.Luxferus:BAAANQAECgQICAAAAA==.Luxzilla:BAAANQAECgEIAQAAAA==.',
Ly='Lyanara:BAAANQAECgUICQAAAA==.Lyican:BAAANQAECgQIBgAAAA==.Lyndsay:BAAANQADCgcIDAAAAA==.',
Ma='Macroo:BAAANQADCgEIAQAAAA==.Madamkitty:BAAANQAECgEIAQAAAA==.Madmat:BAAANQADCgYICQAAAA==.Maekaros:BAAANQADCgEIAQAAAA==.Maeliora:BAAANQADCgUIBQAAAA==.Maenix:BAAANQADCgYICgAAAA==.Magarithas:BAAANQAECgcIDQAAAA==.Magdie:BAAANQAECgYICgAAAA==.Magicbuns:BAAANQABCgUIBgAAAA==.Magicdevil:BAAANQADCgUIBQAAAA==.Magicmiike:BAAANQAECgIIAgAAAA==.Magicundies:BAAANQADCgUIBQAAAA==.Magiedoesit:BAAANQABCgIIAgAAAA==.Magikz:BAAANQADCgYIDQAAAA==.Maginitis:BAAANQAECgYICgAAAA==.Magsissippi:BAAANQADCgYIBgAAAA==.Mahoragah:BAAANQADCgUIDgAAAA==.Mahune:BAAANQADCggICwAAAA==.Malacandia:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Malacanth:BAAANQADCgYIDQAAAA==.Malfuria:BAAANQADCgYIDAAAAA==.Maltorias:BAAANQAECgUIBQAAAA==.Mammamilker:BAAANQADCgQIBAAAAA==.Managed:BAAANQADCgcIFQAAAA==.Manaplz:BAEANQABCgYIBwABNQADCggIFAABAAAAAA==.Mandopan:BAAANQADCgUIBQAAAA==.Mandroes:BAAANQADCgYIBgAAAA==.Manga:BAAANQADCgcIBwAAAA==.Mannheim:BAAANQAECgEIAQAAAA==.Mannydamanly:BAAANQAECgUIBQAAAA==.Manwei:BAAANQADCgQIBAAAAA==.Mapes:BAAANQADCgEIAQAAAA==.Mapleoats:BAAANQADCgcICwAAAA==.Maplepally:BAAANQAECgQIBQAAAA==.Mardel:BAAANQAECgcIEAAAAA==.Markymeta:BAAANQAECgQIBQAAAA==.Markymogging:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Martyrdom:BAAANQAECgYICwAAAA==.Marék:BAAANQADCgQIBAAAAA==.Masubi:BAAANQADCggIDAABNQAECgQIBQABAAAAAA==.Mathilda:BAAANQADCgEIAQAAAA==.Mattdh:BAAANQAECgUIBgABNQAECgcIBwABAAAAAA==.Mayjah:BAAANQAECgYIDQAAAA==.Mazzorz:BAAANQADCgQIBAAAAA==.',
Mc='Mcmoonie:BAAANQADCggICAABNQAECgcIDwABAAAAAA==.Mcscooterson:BAAANQAECgEIAQAAAA==.',
Me='Mechegidius:BAAANQAECgMIBAAAAA==.Meenja:BAAANQAECgQICAAAAA==.Meeseomelete:BAAANQADCggIEQAAAA==.Mehrunez:BAAANQABCgEIAQABNQADCggIFAABAAAAAA==.Mekademuerte:BAAANQADCggIEgAAAA==.Melady:BAAANQAECgIIAgAAAA==.Melisity:BAAANQAECgMIAwAAAA==.Mellamoalex:BAAANQABCgUIBgAAAA==.Mellodic:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Melïnoe:BAAANQADCgMIAwAAAA==.Menamaga:BAAANQADCgcIDwAAAA==.Mentycles:BAAANQAECgEIAQAAAA==.Mercedis:BAAANQAECgUIDAAAAA==.Merydeath:BAAANQADCgQIBwAAAA==.Mevo:BAAANQADCgMIAwAAAA==.',
Mi='Miazma:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Mids:BAAANQADCggIEwAAAA==.Mihira:BAAANQAECgMIBQAAAA==.Miinii:BAAANQADCgUIBQAAAA==.Mikeangel:BAAANQAECgEIAQAAAA==.Mintweaver:BAAANQADCgYIBgAAAA==.Miracrystal:BAAANQADCggICAAAAA==.Misereatur:BAAANQABCgYICgAAAA==.Misofluffeh:BAAANQADCgYIBgAAAA==.Mistaaytch:BAAANQADCggIDQAAAA==.Mistika:BAAANQAECgEIAgABNQAECgcIEAABAAAAAA==.Mithrandyr:BAAANQAECgMIAwABNQAECgYIDAABAAAAAA==.Mitigates:BAAANQADCgYICwABNQADCggICAABAAAAAA==.',
Mn='Mnimi:BAAANQAECgQIBQAAAA==.',
Mo='Monkabô:BAAANQADCgEIAQAAAA==.Monkeballs:BAAANQAFFAEIAgAAAA==.Monkqi:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Monkâs:BAAANQAECgQICAAAAA==.Monstacardo:BAAANQAECgUICQAAAA==.Mooncaliber:BAAANQAECgQIBQAAAA==.Moondrala:BAAANQAECgQICAAAAA==.Moonnshadow:BAAANQADCgQIBAABNQADCgcIFAABAAAAAA==.Moonyy:BAAANQADCgQIBAAAAA==.Mootodeath:BAAANQADCgYICAAAAA==.Mordsîth:BAAANQAECgEIAQAAAA==.Morgona:BAAANQADCgUICAAAAA==.Morrin:BAAANQAECgIIAgAAAA==.Moîraine:BAAANQAECgEIAQAAAA==.',
Mu='Mudslide:BAAANQADCgYIEQAAAA==.Mujojo:BAAANQADCgIIAgAAAA==.Mulciber:BAAANQADCggIDwAAAA==.Mulsi:BAAANQADCgMIAwAAAA==.Muralin:BAAANQADCgEIAQAAAA==.',
My='Mycelia:BAAANQADCgIIAgAAAA==.Myrian:BAAANQAECgIIBAAAAA==.Mysticalmoon:BAAANQADCgYICQAAAA==.',
['Mö']='Möösê:BAAANQAECgIIAgAAAA==.',
Na='Nagafurry:BAAANQADCgcIEgAAAA==.Nahadoth:BAAANQAECgIIAwAAAA==.Nahas:BAAANQAECgEIAQAAAA==.Nahtee:BAAANQAECgIIAgAAAA==.Naib:BAAANQADCgUIBgAAAA==.Nalaa:BAAANQADCgYIBgAAAA==.Namrathor:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Namruh:BAAANQAECgIIAgAAAA==.Nannydanny:BAAANQAECgQIBQAAAA==.Napless:BAAANQADCgUIBQAAAA==.Narivi:BAAANQAECgQIBQAAAA==.Nathrissa:BAAANQAECgIIAwAAAA==.Natsunoki:BAAANQAECgYIDQAAAA==.Nayati:BAAANQADCgYICQAAAA==.',
Ne='Nebulia:BAAANQAECgEIAQAAAA==.Neddludd:BAAANQAECgQIBAAAAA==.Nelvari:BAAANQAECgEIAQAAAA==.Nennya:BAAANQAECgIIAgAAAA==.Neox:BAAANQADCgIIBAAAAA==.Nephalae:BAAANQAECgEIAQAAAA==.Neredonte:BAAANQAECgEIAQAAAA==.Nevixia:BAAANQAECgMIBAAAAA==.Newc:BAAANQADCgcICQAAAA==.Neò:BAAANQADCgUICgAAAA==.',
Ni='Niallad:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Niaorud:BAAANQADCggICAAAAA==.Nighthood:BAAANQAECgEIAQAAAA==.Nightmanimal:BAAANQADCggIFAABNQAECgMIAwABAAAAAA==.Nightmaven:BAAANQADCgQIBAAAAA==.Nigth:BAAANQAECgEIAQAAAA==.Nihm:BAAANQAECgUICAAAAA==.Nikonrage:BAAANQAECgIIAgAAAA==.Nilofur:BAAANQAECgIIAgAAAA==.Nimarai:BAAANQAECgIIAgAAAA==.Nimbus:BAAANQADCgEIAQAAAA==.Nimrodton:BAAANQADCgcICgAAAA==.Nixxiie:BAAANQAECgQIBAAAAA==.',
No='Noellexd:BAAANQAECgYIBwAAAA==.Nomamor:BAAANQAECgMIAwAAAA==.Noobadin:BAAANQADCgQIBAAAAA==.Normund:BAAANQADCggIFgAAAA==.Notmypaladin:BAAANQAECgEIAQAAAA==.Noveria:BAAANQAECgIIAgAAAA==.Nowhereman:BAAANQABCgMIAwAAAA==.',
Nu='Nuadore:BAAANQADCggIFQAAAA==.Nuca:BAAANQADCggIDAAAAA==.Nuwien:BAAANQAECgUICQAAAA==.',
Nv='Nvme:BAAANQAECgQIBgAAAA==.',
Ny='Nyneave:BAAANQAECgUIBgAAAA==.',
['Nè']='Nèo:BAAANQAECgYICwAAAA==.',
Ob='Oberok:BAAANQADCggIFQAAAA==.',
Og='Ogerslayer:BAAANQADCgYICQAAAA==.Ogproduct:BAAANQAECgMIBAAAAA==.',
Oh='Ohhbiscuits:BAAANQABCgYIBAAAAA==.',
Ok='Okashå:BAAANQAECgIIAgAAAA==.',
Ol='Oleandar:BAAANQAECgQIBgAAAA==.Ollathir:BAAANQADCgcICwAAAA==.Olrox:BAAANQADCgUICwAAAA==.',
Om='Omeguiz:BAAANQAECgMIAwAAAA==.Omni:BAAANQAECgMIAwAAAA==.',
On='Onceapun:BAAANQADCgIIAgAAAA==.Oneunder:BAAANQAECgEIAQAAAA==.',
Op='Opa:BAAANQAECgYIDwAAAA==.Opalore:BAAANQAECgEIAQAAAA==.Oppawinfury:BAAANQAECgYIDQAAAA==.Opportunist:BAAANQAECgIIAgAAAA==.Oppydono:BAAANQAECgYIDQAAAA==.',
Or='Orejon:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Orlon:BAAANQADCgQIBAAAAA==.Oryo:BAAANQADCggIFQABNQAECgYIEAABAAAAAA==.',
Os='Osfume:BAAANQADCgQIBAAAAA==.Oshrom:BAAANQADCgYIDAAAAA==.',
Pa='Paako:BAAANQABCgYIBgAAAA==.Packapunch:BAAANQADCgcIDQAAAA==.Padrebear:BAAANQADCggIDgAAAA==.Pakanokis:BAAANQAECgQIBgAAAA==.Palchodie:BAAANQAECgUIBQAAAA==.Pallywhackit:BAAANQAECgcICQAAAA==.Pancho:BAABNQAECoEXAAIIAAkJoCTaAgCsAwAIAAkJoCTaAgCsAwAAAA==.Panchodk:BAAANQADCgQIBAAAAA==.Panchoxd:BAAANQAECgIIAwAAAA==.Pandemoniuxs:BAAANQAECgYICAAAAA==.Pandomedic:BAEANQADCggIFQABNQAECgEIAQABAAAAAA==.Pangon:BAAANQAECgIIAgAAAA==.Panzerfauste:BAAANQAECgEIAQAAAA==.Paos:BAAANQAECgQIBgAAAA==.Paragøn:BAAANQADCgEIAgABNQAECgIIAgABAAAAAA==.Paratheius:BAAANQAECgIIAgAAAA==.Partz:BAAANQAECgQIBgAAAA==.Patrissia:BAAANQADCgYIBwAAAA==.Pauhunt:BAAANQADCgQIBAAAAA==.',
Pe='Pelleus:BAAANQAECgMIAwAAAA==.Pelzel:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Perdluz:BAAANQAECgQIBQAAAA==.Peuf:BAAANQADCgQIBAAAAA==.Pewpewpants:BAAANQADCgYIBgAAAA==.Peékaboo:BAAANQADCgQIBAAAAA==.',
Ph='Phaidrå:BAAANQADCggIBwAAAA==.Phillidan:BAAANQADCgcIBwAAAA==.Philthy:BAAANQAECgMIAwAAAA==.',
Pi='Pics:BAAANQAECgUICQAAAA==.Piic:BAAANQABCgQIBAAAAA==.Piiff:BAAANQAECgEIAQAAAA==.Piment:BAAANQAECgEIAQAAAA==.Pistóph:BAAANQADCggICAAAAA==.Pixiepops:BAAANQADCgQICwAAAA==.Pizzadahutt:BAAANQAECgQIBwAAAA==.',
Pl='Plstt:BAAANQAECgIIAgAAAA==.Plummita:BAAANQADCgQIBgAAAA==.',
Po='Pokemeplease:BAAANQAECggIEgAAAA==.Policebus:BAAANQADCggIFAAAAA==.Pontos:BAAANQADCgYICgAAAA==.Pooballs:BAAANQADCgMIBgAAAA==.Postmortemx:BAAANQAECgcICgAAAA==.Postullio:BAAANQADCgEIAQAAAA==.Potytrained:BAAANQADCgMIAwAAAA==.Pouncington:BAAANQAECgcIBwAAAA==.Powerbun:BAAANQADCgcIDQAAAA==.',
Pp='Pp:BAAANQAECgEIAQAAAA==.',
Pr='Praevalens:BAAANQADCgYICAAAAA==.Prayerbender:BAAANQAECgYICQAAAA==.Prevokdsaint:BAAANQAECgYIDgAAAA==.Primelus:BAAANQAECgQIBAAAAA==.Procure:BAAANQAECgEIAQAAAA==.',
Ps='Pspspspsps:BAAANQAECgQIBgAAAA==.',
Pu='Pumpi:BAAANQAECgQIBQAAAA==.Purkmcclappy:BAAANQAECgQIBAAAAA==.',
Pw='Pwippin:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.',
Py='Pylytuphous:BAAANQADCgcIBwAAAA==.Pyromarine:BAAANQAECgYICQAAAA==.Pyrräh:BAAANQADCgUIBQAAAA==.',
['Pà']='Pàìn:BAAANQAECgEIAgAAAA==.',
['Pé']='Pétmaster:BAAANQADCgUICQAAAA==.',
['Pù']='Pùff:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.',
Qu='Quactemoc:BAAANQAECgMIBQAAAA==.Queditate:BAAANQAECgUIBgAAAA==.Queragon:BAAANQADCggIEAAAAA==.Quickie:BAAANQAECgYIBQAAAA==.Quintom:BAAANQABCgMIAgAAAA==.',
Qw='Qwallin:BAAANQADCgQIBgAAAA==.Qweb:BAAANQADCgUIBQAAAA==.',
Ra='Raboge:BAEANQADCgcIEgAAAA==.Racarris:BAAANQADCgQIBAAAAA==.Rachelreano:BAAANQAECgMIBAAAAA==.Raevive:BAAANQAECgUICQAAAA==.Raeyne:BAAANQAECgQIBAAAAA==.Rajus:BAAANQADCgIIBAAAAA==.Rakoten:BAAANQADCgIIAgAAAA==.Rallös:BAAANQAECgcIDwAAAA==.Raltan:BAAANQAECgEIAQAAAA==.Ramberth:BAAANQAECgMIBAAAAA==.Ramgorb:BAAANQADCgYIDAAAAA==.Randomdots:BAAANQADCgYIBgAAAA==.Randomhunt:BAAANQAECgcIDgAAAA==.Randomlock:BAAANQAECgIIBAABNQAECgcIDgABAAAAAA==.Rapidcurse:BAAANQADCgUIBQAAAA==.Rathalos:BAAANQADCgcICQAAAA==.Rathma:BAAANQAECgUIDgABNQAECgkJGAAJAHcJAA==.Ratyeeter:BAAANQAECgMIBQAAAA==.Ravarim:BAAANQADCgYIDQABNQADCggIGAABAAAAAA==.Raveen:BAAANQABCgIIBAAAAA==.Ravemister:BAAANQADCgYIBgAAAA==.Ravesorc:BAAANQAECgMIAwAAAA==.Ravix:BAAANQABCgYIBgAAAA==.Rawrdon:BAAANQABCgIIAgABNQAECgQIBAABAAAAAQ==.Rayyvvnn:BAAANQADCgQIBAAAAA==.Razmitaz:BAAANQAECgUIBwAAAA==.Razoir:BAAANQADCgUIBQAAAA==.Razz:BAAANQADCgYICgAAAA==.',
Re='Realdeathtyr:BAAANQAECgMIAwAAAA==.Recherché:BAAANQADCggIEgAAAA==.Redandginger:BAAANQADCgIIBAAAAA==.Redneb:BAAANQAECgMIBAABNQAECgYICQABAAAAAA==.Reigndrops:BAAANQADCgcIEgAAAA==.Reinay:BAAANQADCgMIAwAAAA==.Reindeerr:BAAANQAECgUICAAAAA==.Reiyo:BAAANQADCgIIBAAAAA==.Rektmate:BAAANQABCgUIBAABNQABCgUIBQABAAAAAA==.Relikar:BAAANQAECgMIBAAAAA==.Relsafk:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Reminsheal:BAAANQAECggIBgAAAA==.Renoober:BAAANQADCgUIBQAAAA==.Reservoirtip:BAAANQADCgcIBwAAAA==.Resmè:BAAANQADCggIFAAAAA==.Retx:BAAANQADCgQIBAAAAA==.Revelia:BAAANQADCggIFwAAAA==.Revenger:BAAANQAECgMIAwAAAA==.Revenwind:BAAANQADCgcIEQAAAA==.Revw:BAAANQAECgMIBAAAAA==.Reíka:BAAANQAECgEIAQAAAA==.',
Rh='Rhastia:BAAANQADCggICQAAAA==.Rhezin:BAAANQADCgYIBgAAAA==.Rhynoz:BAAANQAECgYICwAAAA==.Rhäne:BAAANQADCgcICQAAAA==.',
Ri='Richeliue:BAAANQAECgEIAQAAAA==.Rifflizard:BAAANQADCggIFwAAAA==.Riga:BAAANQADCggIDgAAAA==.Righteöus:BAAANQADCgEIAQAAAA==.Rinleigh:BAAANQAECgMIBAAAAA==.Rista:BAAANQAECgMIAwAAAA==.Rizah:BAAANQADCggIEwAAAA==.',
Ro='Robindebrave:BAAANQAECgEIAQAAAA==.Roion:BAAANQADCgcIDQAAAA==.Ronor:BAAANQADCgYIDAAAAA==.Rootbeer:BAAANQABCgMIBQAAAA==.Rorlath:BAAANQAECgMIAwAAAA==.Rosablade:BAAANQABCgQIBgAAAA==.Rotbreath:BAAANQAECgQIBwAAAA==.Rotknees:BAAANQADCgYIEgAAAA==.Roxxùs:BAAANQAECgUICAAAAA==.',
Ru='Ruiinaxx:BAAANQADCgQIBQAAAA==.Runehelm:BAAANQADCgUIBQAAAA==.Runningamonk:BAAANQADCggICAAAAA==.Rupaull:BAAANQADCgcIDwAAAA==.Ruruk:BAAANQADCgcIDQAAAA==.Ruthlessly:BAAANQAECgUIBwAAAA==.',
Rw='Rwby:BAAANQAECgQIBgAAAA==.',
Ry='Rydrion:BAAANQAECgQIBQAAAA==.Rykah:BAAANQAECgIIAgAAAA==.Ryndasa:BAAANQAECgIIAgAAAA==.Rynnifer:BAAANQAECgQICAAAAA==.Ryshot:BAAANQADCgYIDgAAAA==.Ryúk:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràyne:BAAANQAECgMIAwAAAA==.',
['Ré']='Répent:BAAANQAECgMIBAAAAA==.',
Sa='Sabbie:BAABNQAFFIEHAAIKAAUJ0Q6nAQCjAQAKAAUJ0Q6nAQCjAQAAAA==.Sabrael:BAAANQAECgUICAAAAA==.Sabryelle:BAAANQADCgUICQAAAA==.Sadburrito:BAAANQADCggIEQAAAA==.Saddiel:BAAANQAECgEIAQAAAA==.Saer:BAAANQAECgUIBwAAAA==.Saevromauch:BAAANQADCgcIDwAAAA==.Safè:BAAANQAECgEIAgABNQAFFAEIAwABAAAAAA==.Sageoffan:BAAANQAECgQIBAAAAA==.Sajah:BAAANQADCgcIEQAAAA==.Salenastus:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Sallylock:BAAANQADCgYICQAAAA==.Salvatiion:BAAANQADCgYICgAAAA==.Samareith:BAAANQADCgYICwABNQAECgMIAwABAAAAAA==.Samberg:BAAANQAECgYICgAAAA==.Sandstalker:BAAANQAECgcIDQAAAA==.Sangwhen:BAAANQAECgIIAgAAAA==.Saphyria:BAAANQAECgMIAwAAAA==.Saraplegic:BAAANQAECgMIAwAAAA==.Sareene:BAAANQAECgQIBQAAAA==.Sargaerin:BAAANQABCgEIAQAAAA==.Saroku:BAAANQAECgIIAgAAAA==.Sarraah:BAAANQADCggIDQAAAA==.Saturnia:BAAANQADCgcIEgAAAA==.Savannay:BAAANQAECgQICgAAAA==.Saül:BAAANQADCggIDQAAAA==.',
Sb='Sbjarl:BAAANQADCgMIAwAAAA==.',
Sc='Schnozz:BAAANQAECgUIBwAAAA==.Schnozzdruid:BAAANQADCgYICwABNQAECgUIBwABAAAAAA==.Scry:BAAANQAECgQIBAAAAA==.',
Se='Searenity:BAAANQAECgQIBAABNQAECgYICQABAAAAAA==.Sefiron:BAAANQAECgMIAwAAAA==.Sejam:BAAANQADCgIIAgAAAA==.Sejeong:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Selfheals:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Semmiramis:BAABNQAECoEXAAILAAkJVyL0CAAUAwALAAkJVyL0CAAUAwAAAA==.Seria:BAAANQAECgMIBAAAAA==.Severus:BAAANQAECgQIBgAAAA==.Señorass:BAAANQADCggICAAAAA==.',
Sh='Shadowone:BAAANQADCgEIAwAAAA==.Shadowswîper:BAAANQADCggICAAAAA==.Shadowthrone:BAAANQADCgUIDgAAAA==.Shakavoodoo:BAAANQABCgUIBQAAAA==.Shamage:BAAANQAECgQICAAAAA==.Shamette:BAAANQADCggIDQAAAA==.Shamwise:BAAANQADCgcIDQAAAA==.Shannongram:BAAANQADCgYICgAAAA==.Shard:BAAANQADCgcICQAAAA==.Shardmist:BAAANQAECgMIAwAAAA==.Sharese:BAAANQADCggICAAAAA==.Shashara:BAAANQADCgMIAwABNQAECgUIBwABAAAAAA==.Shawtyblastn:BAAANQAECgIIAgAAAA==.Shayla:BAAANQAECgEIAQAAAA==.Shaî:BAEANQAECgEIAQAAAA==.Shellager:BAAANQADCgcIEQAAAA==.Shenrón:BAAANQAECgEIAQAAAA==.Shicon:BAAANQADCgYICgABNQADCgcICwABAAAAAA==.Shinhann:BAAANQADCgMIBQAAAA==.Shinigämï:BAAANQAECgMIBAAAAA==.Shinlong:BAAANQADCgYICQAAAA==.Shinochu:BAAANQADCggICAAAAA==.Shkwippin:BAAANQADCggIEgAAAA==.Shoccdoc:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.Shockon:BAAANQAECgQIBAAAAQ==.Shortkeg:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Shotelemento:BAAANQAECgMIAwAAAA==.Shotstuff:BAAANQAECgMIBAAAAA==.Shredders:BAAANQAECgYICwAAAA==.Shrug:BAAANQADCgYICQAAAA==.Shutup:BAAANQADCggIFAAAAA==.',
Si='Siegmeyer:BAAANQADCgEIAQAAAA==.Silverembers:BAAANQAECgMIBAAAAA==.Silverskin:BAAANQAECgEIAQAAAA==.Silverstryke:BAAANQAECgMIAwAAAA==.Sinndelle:BAAANQADCgUIBAAAAA==.Sithic:BAAANQAECggIAwAAAA==.Sithmagic:BAAANQADCggICAAAAA==.',
Sk='Skillasaurus:BAAANQAECgYICwAAAA==.Skitaepo:BAAANQAECgQICAAAAA==.Skoalstrait:BAAANQADCgQIBgAAAA==.Skou:BAAANQAECgcIDQAAAA==.Skozer:BAAANQADCggIDQAAAA==.Skycaptaín:BAAANQAECgQICAAAAA==.Skyraptor:BAAANQADCggICAAAAA==.Skúld:BAAANQADCgYICgAAAA==.',
Sl='Slapntickles:BAAANQAECgQIBQAAAA==.Slayy:BAAANQAECgEIAQAAAA==.Sleepies:BAAANQADCgYIBgABNQAECgcICwABAAAAAA==.',
Sm='Smacks:BAAANQADCgUIBQAAAA==.Smallarcana:BAAANQAECgQIBQAAAA==.Smashy:BAAANQAECgIIAgAAAA==.Smea:BAAANQAECgEIAQAAAA==.Smenalpha:BAAANQADCgMIAwAAAA==.Smhlol:BAAANQAECgUIBgAAAA==.Smoothblade:BAAANQAECgQIBAAAAA==.',
Sn='Sniffany:BAAANQADCgQIBQAAAA==.',
So='Sofiel:BAAANQAECgEIAQAAAA==.Solae:BAAANQAECgEIAQAAAA==.Solarion:BAAANQAECggICAAAAA==.Solemnoath:BAAANQADCgEIAQAAAA==.Sorbanos:BAAANQADCgYICQAAAA==.Sorlon:BAAANQADCgUIBgAAAA==.Sosmor:BAAANQADCggIEQAAAA==.Souldevil:BAAANQADCgYIDQABNQAECgQIBgABAAAAAA==.Soullessw:BAAANQAECgQIBAAAAA==.Soulweave:BAAANQAECgQIBgAAAA==.Soupsandwich:BAAANQABCgQIBAAAAA==.',
Sp='Sparkiie:BAAANQADCgEIAQAAAA==.Sparklehands:BAAANQAECgEIAQAAAA==.Sparklezs:BAAANQADCgcIEgAAAA==.Specterdh:BAAANQAECgEIAgAAAA==.Specterpal:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Sphyx:BAAANQABCgEIAQAAAA==.Spitty:BAAANQADCggIFAAAAA==.Spooky:BAAANQADCgEIAQAAAA==.Spoonfeed:BAAANQAECgQICAAAAA==.Sputtin:BAAANQAECgUICQAAAA==.',
St='Stabbyshadow:BAAANQADCgYICgAAAA==.Stabbyspydr:BAAANQAECgEIAQAAAA==.Stackz:BAAANQAECgYICwAAAA==.Starbreakêr:BAAANQADCgYIBwAAAA==.Starbun:BAAANQAECgQIBQAAAA==.Staszia:BAAANQAECgQIBAAAAA==.Steeleyé:BAAANQADCggIEAAAAA==.Stellarosa:BAAANQADCggIDgAAAA==.Stemihunter:BAEANQAECgEIAQAAAA==.Stemislayer:BAEANQADCgYIBgABNQAECgEIAQABAAAAAA==.Stepdrasta:BAAANQAECgEIAQAAAA==.Stepstone:BAAANQADCgUICwAAAA==.Stonedove:BAAANQAECgIIAgAAAA==.Stonemonk:BAAANQAECgEIAQAAAA==.Stonewalljay:BAAANQAECgQIBQAAAA==.Stont:BAAANQADCgEIAQAAAA==.Stormienite:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.Strikeback:BAAANQADCgUIBQAAAA==.Strzyga:BAEANQAECgYICwAAAA==.Sttygian:BAAANQAECgQIBgAAAA==.Stãtic:BAAANQADCgUIBQAAAA==.',
Su='Subbywubby:BAAANQAECgIIAgAAAA==.Submissa:BAAANQAECgIIAgAAAA==.Subtleshrike:BAAANQAECgQIBgAAAA==.Sugar:BAAANQAECgQIBgAAAA==.Sumalaht:BAAANQADCgQIBQAAAA==.Supliciel:BAAANQAECgUICAAAAA==.Supremus:BAAANQADCgYIBgABNQAECgcICQABAAAAAA==.Sutolshirak:BAAANQADCgQIBQAAAA==.',
Sw='Switchyy:BAAANQADCgUICAAAAA==.Swordon:BAAANQABCgYIBwABNQAECgQIBAABAAAAAQ==.',
Sy='Sydthesquid:BAAANQADCgEIAQAAAA==.Sylerria:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Sylvanir:BAAANQADCgQIBAAAAA==.Sylviefae:BAAANQADCggICgAAAA==.',
['Sá']='Sátan:BAAANQADCgEIAQAAAA==.',
['Sä']='Säcrilege:BAAANQADCgUIBQAAAA==.',
['Sé']='Sévén:BAAANQAECgIIAgAAAA==.',
['Sí']='Sínfùl:BAAANQADCgIIAgAAAA==.',
['Sö']='Sölburn:BAAANQADCgQIBwAAAA==.',
Ta='Tachislock:BAAANQADCgYICAAAAA==.Tacokopter:BAAANQADCgYIBgAAAA==.Tacosbringer:BAAANQAECgcIDQAAAA==.Taleen:BAAANQADCgMIAwAAAA==.Tallyri:BAAANQABCgMIAwAAAA==.Talven:BAAANQADCggIEgAAAA==.Talyanna:BAAANQADCgUIBQAAAA==.Tanir:BAAANQADCgEIAQAAAA==.Tankomatic:BAAANQAECgMIBAAAAA==.Tanksnspanks:BAAANQADCgIIAgAAAA==.Tassy:BAAANQADCgcIDAAAAA==.Tavery:BAAANQADCgUIBQAAAA==.Tavick:BAAANQAECgMIAwAAAA==.',
Te='Teddyboy:BAAANQADCgcIEwAAAA==.Teenis:BAAANQADCgcIEgAAAA==.Tehdeath:BAAANQAECgEIAQAAAA==.Teiela:BAAANQADCgUIBQABNQADCgYIDQABAAAAAA==.Tekin:BAAANQADCggIDgAAAA==.Tenyris:BAAANQAECgQICAAAAA==.Teslinna:BAAANQAECgMIAwAAAA==.Testackles:BAAANQAECgYICwAAAA==.',
Tf='Tft:BAAANQADCggICgABNQAECgkJGQAMAGkSAA==.Tftmonk:BAAANQAECgQIBQABNQAECgkJGQAMAGkSAA==.',
Th='Thadorblor:BAAANQADCgIIBAAAAA==.Thaghuen:BAAANQAECgIIAgAAAA==.Thanazudon:BAAANQAECgYICwAAAA==.Thardras:BAAANQADCggIFgAAAA==.Thatbish:BAAANQABCgQICAAAAA==.Thauria:BAAANQAECgIIAgAAAA==.Theantilynd:BAAANQAECgQICAAAAA==.Thedh:BAAANQADCgYIBgAAAA==.Thelegendary:BAAANQAECggIEgAAAA==.Themoofather:BAAANQADCgMIAwAAAA==.Thenära:BAAANQAECgYICwAAAA==.Thibbledank:BAAANQADCgYIAgAAAA==.Thickbrews:BAAANQADCgYIBgAAAA==.Thorakor:BAAANQADCggICAAAAA==.Thorgrihm:BAEANQADCggIEwAAAA==.Thoriden:BAAANQADCgcIDQAAAA==.Threslor:BAEBNQAECoEgAAINAAkJMyD6BQAuAwANAAkJMyD6BQAuAwAAAA==.Thul:BAAANQADCgcICQAAAA==.Thulkai:BAAANQADCgQIBAAAAA==.Thundaira:BAAANQADCgUIBgAAAA==.Thunderkong:BAAANQADCgEIAQAAAA==.Thurbin:BAAANQADCgYIBgAAAA==.Thurrin:BAAANQAECgMIBQAAAA==.Thysdom:BAAANQADCgYIBgAAAA==.',
Ti='Tiancesham:BAAANQADCgcIDQAAAA==.Tieza:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgQIBAAAAA==.Tiktokboom:BAAANQADCgYICQAAAA==.Timebendr:BAAANQADCgYIDgAAAA==.Tingles:BAAANQADCgEIAQAAAA==.Tinybop:BAAANQADCgUIBwAAAA==.Tinylight:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Tipsei:BAAANQADCggIEwABNQAECgIIAgABAAAAAA==.Tipster:BAAANQAECgIIAgAAAA==.Tiryns:BAAANQADCggICAAAAA==.Titantenai:BAAANQAECgQICAAAAA==.',
To='Toasttyy:BAAANQAECgIIAgAAAA==.Tombelaine:BAAANQADCggIEwAAAA==.Tomolak:BAAANQADCggIEwAAAA==.Toolara:BAAANQAECgQIBQAAAA==.Torrential:BAAANQAECggIDAAAAA==.Torrin:BAAANQADCgYIBgAAAA==.Tortelliní:BAAANQADCgYIEAAAAA==.Totemkai:BAAANQAECgIIAgAAAA==.Totemlucky:BAAANQABCgEIAQAAAA==.Totsmagoats:BAAANQAECgUIBwAAAA==.',
Tp='Tpax:BAAANQAECgQIBgAAAA==.',
Tr='Tralanaz:BAAANQAECgMIAwAAAA==.Traler:BAAANQAECgMIBAAAAA==.Tribrid:BAAANQAECgQIBgAAAA==.Tripee:BAAANQADCggIDgAAAA==.Triple:BAAANQADCggIDgAAAA==.Trolan:BAAANQADCggIDAAAAA==.Truchas:BAAANQADCgQIBQAAAA==.Trugwa:BAAANQADCgcICwAAAA==.Trunksjunkie:BAAANQADCgcIEAAAAA==.Truxx:BAAANQADCgQIBAAAAA==.Tràse:BAAANQADCgUIBQAAAA==.Trälér:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Tu='Tui:BAAANQAECgMIBAAAAA==.Tunacanoe:BAAANQABCgYICAAAAA==.Turboignis:BAAANQADCgUICQAAAA==.',
Tw='Twoballors:BAAANQADCgYICAABNQAECgMIBAABAAAAAA==.',
Ty='Tychira:BAAANQAECgEIAQABNQAECgcICwABAAAAAA==.Tylor:BAAANQADCgYIBwAAAA==.Tyragnì:BAAANQADCggIBgAAAA==.Tyrannicãl:BAAANQAECgQIBQAAAA==.Tyrayline:BAAANQABCgQIBAAAAA==.Tyrhonda:BAAANQADCgUIBgAAAA==.',
['Tò']='Tòy:BAABNQAECoEWAAIOAAkJUhc8JwCuAgAOAAkJUhc8JwCuAgAAAA==.',
Uc='Uchawi:BAAANQADCggIFgAAAA==.',
Ud='Udriel:BAAANQAECgYIDQAAAA==.',
Ug='Ugtana:BAAANQADCgUICgAAAA==.',
Uh='Uhohbehindu:BAAANQADCgcIEgAAAA==.Uhrich:BAAANQAECgUICQAAAA==.',
Ul='Ulithes:BAAANQADCgEIAQAAAA==.Ulruk:BAAANQADCgYIDQAAAA==.Ulthar:BAAANQADCgMIBAAAAA==.',
Um='Umtra:BAAANQAECgIIAgAAAA==.',
Un='Undruin:BAAANQADCgQIBAAAAA==.',
Ur='Urel:BAAANQADCggIBwAAAA==.Ursinlock:BAAANQADCggIFAAAAA==.',
Us='Usedtobe:BAAANQABCgEIAQABNQABCgUIBQABAAAAAA==.',
Uw='Uwukong:BAAANQADCgcICgAAAA==.',
Va='Vaguard:BAAANQAECgEIAQAAAA==.Valadriel:BAAANQADCgUIDgAAAA==.Valarundkil:BAAANQAECgMIAwAAAA==.Valeryi:BAAANQADCgUIBQAAAA==.Valinda:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Valrion:BAAANQADCgUIBQAAAA==.Vampcorpse:BAAANQADCgYICwAAAA==.Vanalleigh:BAAANQADCgUIBQAAAA==.Vanastara:BAAANQAECgQIBAAAAA==.Vanimar:BAAANQAECgQIBQAAAA==.Vanthrain:BAAANQADCgYICwAAAA==.',
Ve='Vegadrood:BAAANQADCggIBwAAAA==.Velashar:BAAANQAECgIIAgAAAA==.Veleina:BAAANQADCgcIBwAAAA==.Veletari:BAAANQAECgUIBgAAAA==.Veliinna:BAAANQAECgEIAQAAAA==.Vellius:BAAANQADCgEIAQAAAA==.Venkukrugar:BAAANQAECgEIAQAAAA==.Venndia:BAAANQADCgQIBAAAAA==.Vergie:BAAANQAECgYIDQAAAA==.Verraden:BAAANQADCgQIBAAAAA==.Verritas:BAAANQADCgYIDQAAAA==.Versiana:BAAANQAECgQIBQABNQAECgQIBQABAAAAAA==.Vesperly:BAAANQAECgQIBAAAAA==.Vesso:BAAANQAECgQIBwAAAA==.Veximeksar:BAAANQADCgUIBQAAAA==.Vexxn:BAAANQADCggIFAAAAA==.',
Vi='Villis:BAAANQAECgMIAwAAAA==.Vintrador:BAAANQAECgQIBAAAAA==.Visike:BAAANQADCgIIAgAAAA==.Vixson:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.',
Vo='Voidla:BAAANQAECgEIAQAAAA==.Voidshank:BAAANQAECgEIAQAAAA==.Voltamatron:BAAANQAECgcICQAAAA==.Volunda:BAAANQADCgYIBQABNQAECgQICAABAAAAAA==.Vonbae:BAAANQABCgYICAAAAA==.Vondread:BAAANQABCgIIAgAAAA==.Vorthall:BAAANQAECgQICAAAAA==.',
Vr='Vraaxx:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Vragarr:BAAANQADCgcIBwAAAA==.Vrithea:BAAANQAECgYIDQAAAA==.',
Vy='Vyn:BAAANQADCggIEwAAAA==.Vyndroll:BAAANQADCgQICQAAAA==.Vyrelion:BAAANQADCggIFQAAAA==.Vyri:BAAANQADCggIDgAAAA==.',
['Vë']='Vërastrasza:BAAANQADCggIDQAAAA==.',
['Vó']='Vóidberg:BAAANQADCggIFAAAAA==.',
['Vô']='Vôidweaver:BAAANQABCgIIAgAAAA==.',
Wa='Wangbusan:BAAANQAECgcIDgAAAA==.Wargodmage:BAAANQADCgYIBgAAAA==.Warpedsoul:BAAANQABCgIIAgABNQAECgQIBgABAAAAAA==.Warpone:BAAANQADCgUICQAAAA==.Warrtag:BAEANQAECgYICwAAAA==.Warsella:BAAANQADCgYIDwAAAA==.Warvar:BAAANQADCggIGAAAAA==.Warziilla:BAAANQADCggIDgAAAA==.Wazzard:BAAANQAECgIIAwAAAA==.',
We='Weaz:BAAANQAECgYIDQAAAA==.Weisong:BAAANQAECggIDQAAAA==.Wenyu:BAAANQADCgEIAQAAAA==.',
Wh='Whitelechuga:BAAANQADCggIEAAAAA==.Whorvold:BAAANQADCggIFQAAAA==.Whulf:BAAANQAECgEIAQAAAA==.',
Wi='Wickedllama:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.Wickedsaint:BAAANQADCgYIBgAAAA==.Width:BAAANQADCgUIBQAAAA==.Wildcatt:BAAANQAECgEIAQAAAA==.Wilier:BAAANQAECgMIAwAAAA==.Wiliest:BAAANQADCggICAAAAA==.Willemdafel:BAAANQADCgYIBgAAAA==.Willim:BAAANQABCgQIBAABNQADCgYIBgABAAAAAA==.Willsmith:BAABNQAECoEWAAIEAAgJ4yDJCQAFAwAEAAgJ4yDJCQAFAwAAAA==.Winda:BAAANQAECgMIAwAAAA==.Windwut:BAAANQADCgUIBQAAAA==.',
Wo='Wolfiew:BAAANQADCgUIBQAAAA==.Wolfiez:BAAANQAECgMIAwAAAA==.Wompster:BAAANQAECgcIDwAAAA==.Wompyp:BAAANQADCgcIBwABNQAECgcIDwABAAAAAA==.',
Wr='Wraithtenai:BAAANQAECgQIBwAAAA==.',
Wu='Wuggadari:BAAANQADCggIEQAAAA==.Wulfhardt:BAAANQADCgUIBQAAAA==.Wullun:BAAANQAECgQIBgAAAA==.Wutupnaga:BAAANQADCgEIAQAAAA==.',
Wy='Wymond:BAAANQADCggICgAAAA==.',
['Wá']='Wárlock:BAAANQADCgYICQAAAA==.',
['Wî']='Wîntër:BAAANQABCgEIAQAAAA==.',
Xa='Xaikar:BAAANQAECgEIAQAAAA==.Xanadrill:BAAANQADCgcIEQABNQAECgEIAQABAAAAAA==.Xanatriius:BAAANQAECgQICAAAAA==.Xandiros:BAAANQAECgMIBQAAAA==.Xaveris:BAAANQADCgQIBAAAAA==.Xaviethan:BAAANQAECgMIBAAAAA==.',
Xe='Xerces:BAAANQADCgYIBwAAAA==.Xerrus:BAAANQAECgQIBAAAAA==.',
Xi='Xiang:BAAANQADCgYIBwAAAA==.Xianwae:BAAANQADCgYIBgAAAA==.',
Xo='Xoogle:BAAANQAECgEIAQAAAA==.',
Ya='Yazra:BAAANQAECgIIAwAAAA==.',
Ye='Yensolo:BAAANQAECgEIAQAAAA==.Yetidk:BAAANQAECgIIAgAAAA==.Yetidrood:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Yl='Ylia:BAAANQAECgMIAwAAAA==.Ylvara:BAAANQADCgMIAwABNQAECgYIDQABAAAAAA==.',
Yo='Youbuyquez:BAAANQAECgMIBAAAAA==.',
Yu='Yunky:BAAANQADCgUIBQAAAA==.',
Yv='Yvaelle:BAAANQAECgYICAAAAA==.Yvaelyn:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.',
['Yô']='Yôkai:BAAANQADCgEIAQAAAA==.',
Za='Zacycrockett:BAAANQADCgEIAQAAAA==.Zakomustag:BAAANQADCgEIAQAAAA==.Zalrot:BAAANQAECgQIBgAAAA==.Zandér:BAAANQADCggIEwAAAA==.Zanpa:BAAANQADCggIFAAAAA==.Zantriana:BAAANQAECgEIAQAAAA==.Zappipappi:BAAANQADCgUICQAAAA==.Zaraendice:BAAANQADCggIDAAAAA==.Zarcane:BAAANQAECgEIAQAAAA==.Zarics:BAAANQAECgIIAgAAAA==.',
Ze='Zeebrina:BAAANQAECgEIAQAAAA==.Zel:BAAANQADCgIIAgABNQADCgQIBwABAAAAAA==.Zellerra:BAAANQAECgIIAgAAAA==.Zellock:BAAANQADCgcIBwAAAA==.Zeltar:BAAANQADCggIDAAAAA==.Zephrl:BAAANQADCgYIBwABNQAECgQIBgABAAAAAA==.Zephrul:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.Zesper:BAAANQAECggIDgAAAA==.Zetukur:BAAANQADCgcIDgAAAA==.Zevali:BAAANQABCgQIBgAAAA==.',
Zo='Zorrõ:BAAANQADCgYIBgAAAA==.',
Zu='Zugpo:BAAANQAECgQICAABNQAECgYIDAABAAAAAA==.Zuliena:BAAANQADCgQIBAAAAA==.Zumela:BAAANQAECgIIAgAAAA==.Zuphrel:BAAANQAECgQIBgAAAA==.Zuunau:BAAANQADCgYIBgAAAA==.',
Zw='Zwara:BAAANQADCgcICwAAAA==.',
Zy='Zylander:BAAANQAECgcIDAAAAA==.Zyrek:BAAANQAECgYICAAAAA==.',
['Zá']='Zápdos:BAAANQADCggIFQAAAA==.',
['Zé']='Zéphyre:BAAANQAECgYICQAAAA==.',
['Zì']='Zìlk:BAAANQAECgIIAQAAAA==.',
['Zô']='Zôltan:BAAANQADCgYIDgAAAA==.',
['Àg']='Àgrezar:BAAANQADCgEIAQAAAA==.',
['Âe']='Âerô:BAAANQAECgQICAAAAA==.',
['Æm']='Æmpty:BAAANQADCgUIBQAAAA==.',
['Ês']='Êsôtêrîc:BAAANQADCgEIAQAAAA==.',
['Ðe']='Ðeathstrøke:BAAANQAECgEIAQAAAA==.',
['Ør']='Øreø:BAAANQADCggICAAAAA==.',
['Ùt']='Ùthér:BAAANQAECggIAgAAAA==.',
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
