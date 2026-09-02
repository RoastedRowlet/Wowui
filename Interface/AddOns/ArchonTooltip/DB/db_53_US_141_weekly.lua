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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer',}
local provider = {region='US',realm='Lightbringer',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abahdon:BAAANQAECgMIAwAAAA==.',
Ac='Acanarina:BAAANQADCggIDgAAAA==.Acechapman:BAAANQADCggIDgAAAA==.Aclys:BAAANQAECgQIBQAAAA==.',
Ad='Adam:BAAANQAECgMIBAAAAA==.Adamrobert:BAAANQADCgUIBQAAAA==.Adamuss:BAAANQAECgYICQAAAA==.Addiknight:BAAANQAECgEIAQAAAA==.Adonija:BAAANQADCgYICgAAAA==.Adrenalynn:BAAANQADCggIDAAAAA==.Adriyel:BAAANQADCggIDQAAAA==.',
Ae='Aegisfang:BAAANQADCggICgAAAA==.Aegisrend:BAAANQAECgEIAQAAAA==.Aegrias:BAAANQADCgcIBwABNQAECgYICQABAAAAAA==.Aellgosa:BAAANQADCggIDwAAAA==.Aelorias:BAAANQADCgIIAgAAAA==.Aeniras:BAAANQADCgEIAQAAAA==.Aerelyn:BAAANQADCgYIBgABNQADCggICwABAAAAAA==.',
Af='Aflanna:BAAANQADCgYIBgAAAA==.Aforceuser:BAAANQADCgIIAgAAAA==.Aftershock:BAAANQADCgUICgABNQAECgMIBAABAAAAAA==.',
Ag='Aggressive:BAAANQADCggICQAAAA==.Agi:BAAANQADCgUIBQAAAA==.',
Ah='Ahlea:BAAANQADCggICQAAAA==.Ahnkoh:BAAANQADCgYIBgAAAA==.Ahu:BAAANQADCgMIAwAAAA==.',
Ak='Akader:BAAANQADCggICQAAAA==.Akkarín:BAAANQADCggICAAAAA==.Akróasis:BAAANQADCggICQAAAA==.',
Al='Alahard:BAAANQADCgYICgAAAA==.Alariena:BAAANQAECgQIBAAAAA==.Alassé:BAAANQADCggICAAAAA==.Alcia:BAAANQAECgEIAgAAAA==.Aldrimonk:BAAANQADCgcIBwAAAA==.Aleidari:BAAANQAECgEIAQAAAA==.Alenalee:BAAANQADCggIDgAAAA==.Alexiia:BAAANQADCgIIBAAAAA==.Alfurael:BAAANQADCggIDgAAAA==.Alisynn:BAAANQAECgMIBAAAAA==.Alleriaa:BAAANQADCggIFQAAAA==.Alloryan:BAAANQADCggIDgAAAA==.Alltiedslam:BAAANQADCgQIBgAAAA==.Alstair:BAAANQAECgMIAwAAAA==.Alythria:BAAANQADCgUIBQAAAA==.Alyzei:BAAANQADCggIEgAAAA==.',
Am='Amaryianul:BAAANQADCgMIAwAAAA==.Ambroesia:BAAANQADCgIIBAAAAA==.Ambulance:BAAANQAECgIIAwABNQAECgQIBAABAAAAAA==.Amelsea:BAAANQAECgEIAQAAAA==.Amilgaoul:BAAANQADCgQIBAAAAA==.Amá:BAAANQADCgcIDgAAAA==.',
An='Anabanana:BAAANQABCgMIAwAAAA==.Anachron:BAAANQADCgYICgAAAA==.Anasrastra:BAEANQADCgIIAgABNQADCggIDgABAAAAAA==.Anastassia:BAAANQADCgUICAABNQAECgIIAgABAAAAAA==.Anderdingus:BAAANQAECgEIAQAAAA==.Andrii:BAAANQABCgMIAQAAAA==.Android:BAAANQAFFAIIAgAAAA==.Andrà:BAAANQAECgEIAQAAAA==.Anebriated:BAAANQAECgEIAQAAAA==.Angelice:BAAANQADCgUICAAAAQ==.Angrylock:BAAANQADCgQIBAAAAA==.Animaníac:BAAANQADCgYICgAAAA==.Animosity:BAAANQADCgYICQAAAA==.Annamae:BAAANQADCgYICQAAAA==.Anndal:BAAANQAECgEIAQAAAA==.Anokii:BAAANQADCgcICQAAAA==.',
Ao='Aoeganksta:BAAANQAECgQIBAAAAA==.',
Ap='Apnea:BAAANQADCgQIBwAAAA==.',
Aq='Aquadariah:BAAANQAECgIIAgAAAA==.Aquirple:BAAANQADCggIDAAAAA==.',
Ar='Aranin:BAAANQADCgIIBAAAAA==.Arantes:BAAANQADCgYICwAAAA==.Arcais:BAAANQADCggIDQAAAA==.Archibolt:BAAANQADCgIIAgAAAA==.Arcthoradin:BAAANQAECgEIAQAAAA==.Arda:BAAANQAECgQICAAAAA==.Arduanne:BAAANQADCgMIAwAAAA==.Armeth:BAAANQADCgIIAgAAAA==.Armocida:BAAANQADCgQIBAABNQADCgcICgABAAAAAA==.Arnisa:BAAANQADCgUICAABNQADCgYIDAABAAAAAA==.Arthois:BAAANQABCgIIAgAAAA==.Artimuse:BAAANQAECgIIAgAAAA==.Artoo:BAAANQADCgYIBwAAAA==.Artorias:BAAANQADCgcIDAAAAA==.Artorus:BAAANQADCgUICAAAAA==.Arturitifa:BAAANQADCgYIBgAAAA==.',
As='Asahina:BAAANQADCgcIBwAAAA==.Ascendancë:BAAANQAECgEIAgAAAA==.Ashilla:BAAANQADCgcIDAAAAA==.Astartea:BAAANQADCgQIBAAAAA==.Asuriyan:BAAANQADCgQIBAAAAA==.Asuryani:BAAANQAECgQIBAAAAA==.',
At='Atroxin:BAAANQADCggIDgAAAA==.',
Au='Auhdia:BAAANQADCgcICwAAAA==.Aumatar:BAAANQAECgQIBwAAAA==.Aumatara:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.Auramite:BAAANQAECgUICgAAAA==.Aurellya:BAAANQADCgUIBQAAAA==.Aurina:BAAANQADCggIDwAAAA==.Austinpowers:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Autümn:BAAANQADCgYIBgAAAA==.',
Av='Avarim:BAAANQADCggIEAAAAA==.Avirnus:BAAANQADCgUICAAAAA==.Avsapallybro:BAAANQADCgYICwAAAA==.',
Ax='Axaelle:BAAANQADCgYIBgAAAA==.Axebob:BAAANQADCgIIAgAAAA==.Axesis:BAAANQADCgUICAAAAA==.Axhell:BAAANQADCgQIBAAAAA==.',
Ay='Ayalei:BAAANQAECgEIAgAAAA==.Ayana:BAAANQADCggICAAAAA==.',
Az='Azalle:BAAANQAECgQIBAAAAQ==.Azarell:BAAANQAECgQIBQAAAA==.Azhie:BAAANQAECgQIBAAAAA==.Azkara:BAAANQAECgIIAgAAAA==.Azstraza:BAAANQAECgQIBQAAAA==.Azurelia:BAAANQAECgEIAQAAAA==.Azyrel:BAAANQADCgIIAgAAAA==.',
['Aî']='Aîma:BAAANQAECgIIAwAAAA==.',
Ba='Babbafett:BAAANQAECggIAQAAAA==.Ballofdoom:BAAANQADCggIDgAAAA==.Bamboosifu:BAAANQADCgQIBAAAAA==.Baobunn:BAAANQADCgIIBAAAAA==.Bazzard:BAAANQADCgYIDAAAAA==.',
Bb='Bbellaa:BAAANQADCgMIAwAAAA==.',
Be='Bearhy:BAAANQADCgUICQAAAA==.Bebb:BAAANQADCggIDQAAAA==.Beefychief:BAAANQAECgEIAQAAAA==.Beko:BAAANQAECgQIBQAAAA==.',
Bh='Bhonk:BAAANQADCgIIAgAAAA==.Bhrams:BAAANQAECgIIAgAAAA==.',
Bi='Bibby:BAAANQADCggICAABNQADCgYIBgABAAAAAA==.Bigbahdwolff:BAAANQAECgIIAgAAAA==.Bighugz:BAEANQADCgcIDAAAAA==.Bigjuici:BAAANQAECgIIAgAAAA==.Bigunc:BAAANQAFFAEIAQAAAA==.Billmunny:BAAANQADCgYICwAAAA==.Bismyth:BAAANQADCggICwAAAA==.Bitterblue:BAAANQAECgMIBAAAAA==.',
Bl='Blasphumy:BAAANQADCgUICAAAAA==.Bldk:BAAANQAECgEIAQAAAA==.Bleexx:BAAANQAECgQIBAAAAA==.Blendtec:BAAANQADCgQIBAAAAA==.Blessanay:BAAANQADCgcICwAAAA==.Blightstalkr:BAAANQADCgUIBQAAAA==.Bludnite:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Blueeyestare:BAAANQAECgUIBgAAAA==.Bluefoxy:BAAANQADCgQIBQAAAA==.Blueshock:BAAANQAECggIBAAAAA==.Bluesy:BAAANQAECgQIBAAAAA==.Bluudflagg:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Blüepill:BAAANQADCggIEAABNQAECgYICgABAAAAAA==.',
Bo='Bodåcious:BAAANQAECgQIBAAAAA==.Bokblade:BAAANQAECgMIBAAAAA==.Bonezardo:BAAANQAECgEIAQAAAA==.Boomzel:BAAANQADCgYIBgAAAA==.Boozkin:BAAANQADCgIIAgAAAA==.Bowknight:BAAANQADCgMIAwAAAA==.',
Br='Branze:BAAANQADCgMIAwAAAA==.Brauer:BAAANQAECgEIAQAAAA==.Brecht:BAAANQAECgQIBAAAAA==.Breean:BAAANQADCgYICgAAAA==.Brendia:BAAANQADCgYICQAAAA==.Breylla:BAAANQAECgIIAgAAAA==.Brinze:BAAANQADCgYIBgAAAA==.Brisquik:BAAANQADCgYIDQAAAA==.Brokenheals:BAAANQAECgMIAwAAAA==.Brokenspirit:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Bromax:BAAANQAECgcIDAAAAA==.Bromeatigans:BAAANQAECgEIAQAAAA==.Broncobill:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Bronzebeards:BAAANQABCgEIAQAAAA==.Bronzeblade:BAAANQADCgEIAQAAAA==.Brosef:BAAANQADCgYIBgAAAA==.Brëwdaddy:BAAANQADCggIDgAAAA==.',
Bu='Bubbleurface:BAAANQADCgIIAgAAAA==.Buggy:BAAANQADCgQIBAAAAA==.Bulgogï:BAAANQADCggICQAAAA==.Bunduk:BAAANQADCgcIDAAAAA==.Burnmyeyes:BAAANQADCgQIBAAAAA==.Burrmutt:BAAANQADCgEIAQAAAA==.Butterboi:BAAANQAECgEIAQAAAA==.Buxal:BAAANQADCgcIDAAAAA==.Buzzjägaren:BAAANQADCggIDwAAAA==.',
Bw='Bwe:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
['Bä']='Bällador:BAAANQADCgYIAwAAAA==.',
['Bë']='Bëlen:BAAANQADCgYIBgAAAA==.',
Ca='Cailo:BAAANQADCgcICwAAAA==.Caitrionna:BAAANQADCgUICQABNQADCgYICAABAAAAAA==.Calarraa:BAAANQADCgQIBAAAAA==.Caliasha:BAAANQAECgQIBQAAAA==.Calithdrel:BAAANQADCgYICwAAAA==.Calivoker:BAAANQADCgIIAwABNQADCgYICwABAAAAAA==.Callanan:BAAANQAECgIIAgAAAA==.Calumn:BAAANQADCggIDgAAAA==.Calystaa:BAAANQADCggIDgAAAA==.Camotwo:BAAANQAECgMIBAAAAA==.Caro:BAAANQADCgEIAQAAAA==.Casafrass:BAAANQAECgcICwAAAA==.Cascc:BAAANQADCgUIBQAAAA==.Caspop:BAAANQAECgEIAQAAAA==.Castalia:BAAANQADCgQIBAAAAA==.Catcatchme:BAEANQAECgQIBQAAAA==.Catmaxxing:BAAANQADCgcIBwAAAA==.Cava:BAAANQADCgcIBwAAAA==.Caïtïr:BAAANQADCgYIBgAAAA==.',
Ce='Celebrant:BAAANQAECgEIAQAAAA==.Celendiel:BAAANQADCgUIBQAAAA==.Celicus:BAAANQADCggIDQAAAA==.Celinil:BAAANQADCgQIBAAAAA==.Cenadyen:BAAANQADCgUICgAAAA==.Cerror:BAAANQADCgQIBwAAAA==.Cervantez:BAAANQAECgQIBQAAAA==.',
Ch='Changeforms:BAAANQADCggIDwAAAA==.Chaosmops:BAAANQADCgQIBAAAAA==.Cheekks:BAAANQADCgYICQAAAA==.Cheeseanator:BAAANQADCggIDgAAAA==.Cheestick:BAAANQAECgEIAQAAAA==.Cheif:BAAANQAECgIIAgAAAA==.Cherfslight:BAAANQADCgYIBwAAAA==.Cherishlove:BAAANQADCgQIBAAAAA==.Chezmerelde:BAAANQADCggIDgAAAA==.Choekame:BAAANQADCgYIBgAAAA==.Choopy:BAAANQADCgYICgAAAA==.Chowito:BAAANQAECgEIAQAAAA==.Chromedout:BAAANQADCgcICgAAAA==.Chromme:BAAANQADCgUIDAAAAA==.Chuku:BAAANQADCgUICAAAAA==.',
Ci='Cillia:BAAANQADCgUIBQAAAA==.Cinnabunbun:BAAANQADCgcIDAAAAA==.Cirannis:BAAANQADCgQIBgAAAA==.',
Cl='Cller:BAAANQADCgEIAQABNQADCgYIDAABAAAAAA==.',
Co='Coal:BAAANQAECgEIAQAAAA==.Cocobe:BAAANQADCgYICQAAAA==.Coffeequeene:BAAANQABCgIIAwAAAA==.Coily:BAAANQADCgMIAwABNQADCgYIBwABAAAAAA==.Coni:BAAANQAECgIIAgAAAA==.Conqweefador:BAAANQADCgUIBwAAAA==.Copypasta:BAAANQAECgUIBwAAAQ==.Corghat:BAAANQAECgQIBAAAAA==.Cornfucius:BAAANQAECgcICQAAAA==.Corvinä:BAAANQADCggIDwAAAA==.Courad:BAAANQAECgEIAQAAAA==.',
Cr='Crackalackn:BAAANQADCgIIAgAAAA==.Crackerjill:BAEANQAECgIIAgAAAA==.Crazydwarf:BAAANQADCgYICAAAAA==.Crescendø:BAAANQADCgQIBAAAAA==.Crinkle:BAAANQAECgQIBAAAAA==.Critterx:BAAANQAECgMIBAAAAA==.Crowofwar:BAAANQADCgEIAQAAAA==.Crysilisk:BAAANQAECgQIBAAAAA==.Crystalnight:BAAANQADCggICgAAAA==.',
Cu='Currants:BAAANQADCgQIBAAAAA==.',
Cy='Cyborglol:BAAANQADCggICAAAAA==.Cygani:BAAANQAECgQIBAAAAA==.Cynaesthesia:BAAANQADCgYIBgABNQADCgcICAABAAAAAA==.Cynedrasong:BAAANQAECgQIBAAAAA==.Cynwin:BAAANQADCgcICAAAAA==.',
['Cà']='Càmo:BAAANQAECgEIAQAAAA==.',
['Cä']='Cäkë:BAAANQADCggICgAAAA==.',
['Cè']='Cèrebor:BAAANQADCgIIAgAAAA==.',
Da='Daesi:BAAANQAECgQIBAAAAA==.Dagnorath:BAAANQAECgEIAQAAAA==.Daisydark:BAAANQADCgQIBAAAAA==.Dalika:BAAANQAECgMIBAAAAA==.Dalscars:BAAANQAECgYICQAAAA==.Dancampby:BAAANQADCgMIBQAAAA==.Dankshots:BAAANQAECgcIDQAAAA==.Daphnedowns:BAAANQADCgEIAQAAAA==.Darann:BAAANQAECgIIAgAAAA==.Darkaeris:BAAANQADCgcICgAAAA==.Datash:BAAANQADCggIEAAAAA==.Davyynccii:BAAANQAECgEIAQAAAA==.Dawheight:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Daybringer:BAAANQADCgYICgAAAA==.Daïsy:BAAANQAECgMIBAAAAA==.',
De='Deadcrag:BAAANQAECgMIBAAAAA==.Deadtawko:BAAANQADCggICQAAAA==.Deardra:BAAANQADCggICAAAAA==.Deatherage:BAAANQADCgQIBAABNQADCgcIBwABAAAAAA==.Deathpenance:BAAANQADCgMIAwAAAA==.Deathrazer:BAAANQADCgcIDAAAAA==.Deathsdemon:BAAANQADCgMIBAAAAA==.Deathseeker:BAAANQAECgcIDgAAAA==.Deathwolfs:BAAANQADCgQIBAAAAA==.Decoyfamily:BAAANQADCgcIDQABNQAECgUIBgABAAAAAA==.Dedgathering:BAAANQADCgMIAwAAAA==.Deetours:BAAANQAECgMIBwAAAA==.Deidamia:BAAANQABCgEIAQAAAA==.Deirdra:BAAANQADCgcIBwAAAA==.Delat:BAAANQAECgIIAQAAAA==.Delyssuh:BAAANQAECgQIBAAAAA==.Demyred:BAAANQADCggIDwAAAA==.Denddar:BAAANQADCgUICAAAAA==.Destinyeyes:BAAANQAECgIIAgAAAA==.Deuteros:BAAANQADCgQIBAAAAA==.Devianthunt:BAAANQAECgMIBAAAAA==.',
Df='Dfg:BAAANQAECgQIBQAAAA==.',
Di='Diddledeebum:BAAANQAECgIIAgAAAA==.Dinkysoleil:BAAANQADCgYIBgAAAA==.Disbeliever:BAAANQAECgEIAQAAAA==.Dislustic:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.',
Dk='Dkawesomness:BAAANQADCgYICgAAAA==.',
Dm='Dmc:BAAANQADCgMIAwAAAA==.',
Do='Dokiron:BAAANQADCgUICAAAAA==.Domeki:BAAANQADCgYICgAAAA==.Domimommy:BAAANQAECgEIAQAAAA==.Doomblossom:BAAANQADCgQIBAAAAA==.Doromarius:BAAANQADCgQIBAAAAA==.Dozèr:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.',
Dp='Dpshunter:BAAANQAECgcIDAAAAA==.',
Dr='Draevan:BAAANQAECgQIBQAAAA==.Draglan:BAAANQABCgIIAgAAAA==.Dragonslime:BAAANQADCgYICwAAAA==.Drakkthar:BAAANQADCgMIBAAAAA==.Drakloak:BAAANQADCgYICwAAAA==.Dranae:BAAANQADCgcIBwAAAA==.Dravion:BAAANQAECgIIAgAAAA==.Drazlock:BAAANQADCgIIAgAAAA==.Drcoup:BAAANQADCggIDwAAAA==.Drevin:BAAANQAECgEIAQAAAA==.Drezriel:BAAANQADCggIDgAAAA==.Droodzilla:BAAANQADCgMIAwAAAA==.Dryadius:BAAANQAECgIIAgAAAA==.Dràgón:BAAANQADCgcIDAAAAA==.',
Du='Dualîty:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Duana:BAAANQAECgEIAQAAAA==.Ducksaas:BAAANQADCgUIBQAAAA==.',
Dv='Dvlishadhira:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
Dw='Dwagonbwulgi:BAAANQADCggIDgAAAA==.',
Dy='Dycrons:BAAANQAECgUIBgAAAA==.Dynaohs:BAAANQADCgYICgAAAA==.',
Eb='Ebenzer:BAAANQAECgQIBgAAAA==.Ebenzervoid:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.Ebonomix:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Ebön:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.',
Ec='Eclipsè:BAAANQABCgMIAwAAAA==.',
Ei='Eibon:BAAANQADCgIIAwAAAA==.Eirä:BAAANQADCggICAAAAA==.Eithriand:BAAANQADCgUIBQAAAA==.',
El='Elchræl:BAAANQADCgQIAwAAAA==.Eldadog:BAAANQADCgMIAwAAAA==.Electronik:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Eliesa:BAAANQAECgMIAwABNQAECgQIBQABAAAAAA==.Ellvira:BAAANQAECgMIBAAAAA==.Ellyriax:BAAANQADCggIDwAAAA==.Elsbeth:BAAANQADCgYICwAAAA==.Eltex:BAAANQADCgYICgAAAA==.Elv:BAAANQAECgQIBAAAAA==.Elwisp:BAAANQADCgUIBQAAAA==.',
En='Endlessmoon:BAAANQADCgYIDQAAAA==.Enflexi:BAAANQAECgIIAwAAAA==.Engrave:BAAANQADCgUIBQAAAA==.Entro:BAAANQAECgIIAgAAAA==.',
Eo='Eorana:BAAANQAECgUICAAAAA==.',
Ep='Ephoriah:BAAANQAECgQIBAAAAA==.',
Er='Ericho:BAAANQAECgMIAwAAAA==.Erris:BAAANQAECgEIAQAAAA==.Erunak:BAAANQAECgIIAgAAAA==.',
Es='Estasa:BAAANQADCggIDwAAAA==.',
Et='Ettepriest:BAAANQADCggIDgAAAA==.Ettyn:BAAANQAECgEIAQAAAA==.',
Ev='Everymanimal:BAAANQADCggIDgAAAA==.Evolex:BAAANQAECgIIAgAAAA==.Evollana:BAAANQAECgcIDAAAAA==.',
Ez='Ezith:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
['Eí']='Eín:BAAANQADCgYICwAAAA==.',
['Eñ']='Eñzytë:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.',
Fa='Faalana:BAAANQADCggIDAAAAA==.Failbones:BAAANQAECgYICgAAAA==.Faks:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Falsecrack:BAAANQAECgIIAgAAAA==.Farand:BAAANQAECgEIAQAAAA==.Farnox:BAAANQADCggIDgAAAA==.Fatfurry:BAAANQAECgEIAQAAAA==.Faustirian:BAAANQADCgQIBgAAAA==.Fay:BAAANQADCggIDgAAAA==.',
Fe='Fearsmonk:BAAANQADCgQIBAAAAA==.Felgrihm:BAEANQADCgUICQABNQADCgYICwABAAAAAA==.Felmeup:BAAANQADCgcIDAAAAA==.Feoranne:BAAANQADCggIDgAAAA==.Feralshaman:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Feren:BAAANQAECgQIBAAAAA==.Ferrek:BAAANQABCgIIAgAAAA==.',
Fh='Fhurian:BAEANQADCgUIBQABNQADCgYICwABAAAAAA==.',
Fi='Fi:BAAANQADCggIDwAAAA==.Fiasco:BAAANQADCggIDgAAAA==.Firo:BAAANQADCgMIAwAAAA==.Fisst:BAAANQADCggICwAAAA==.Fistypurk:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Fivecentwarr:BAAANQAECgEIAQAAAA==.',
Fl='Flabby:BAAANQAECgcICAAAAA==.Flandis:BAAANQADCgIIAgAAAA==.Fleurt:BAAANQAECgEIAQAAAA==.Flexxi:BAAANQABCgQIBAAAAA==.Flighent:BAAANQADCgQIBQAAAA==.Floorgodx:BAAANQAECgUIBwAAAA==.Flore:BAAANQADCggIDgAAAA==.Floriinn:BAAANQADCgMIAwAAAA==.Flourish:BAAANQAECgQIBAAAAA==.Flowblue:BAAANQADCgcIBwAAAA==.Flufflles:BAAANQADCgQIBAAAAA==.',
Fo='Fontanä:BAAANQADCgcIDAAAAA==.Food:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Forioss:BAAANQAECgEIAQAAAA==.Forlyfe:BAAANQADCgQIAwAAAA==.Fortyhands:BAAANQADCgcIDQAAAA==.',
Fr='Fractures:BAAANQADCgQIBQAAAA==.Frane:BAAANQAECgEIAQAAAA==.Freakazoíd:BAAANQABCgIIAgAAAA==.Freakly:BAAANQADCgYICwAAAA==.Freesamples:BAAANQADCgIIAgAAAA==.',
Fu='Fubarius:BAAANQADCgMIAwAAAA==.Fullplatefox:BAAANQADCgUICQAAAA==.Funklelock:BAAANQAECgUIBgAAAA==.Furo:BAAANQADCgIIBAAAAA==.Fuzzytek:BAAANQADCgYICgAAAA==.',
Fw='Fweezem:BAAANQABCgIIAgAAAA==.',
Fy='Fyggdrasil:BAAANQADCgUIBAAAAA==.',
['Fé']='Félboots:BAAANQADCgYICQAAAA==.',
Ga='Gadgetwrench:BAAANQADCgQIBAAAAA==.Galenas:BAAANQADCgEIAQAAAA==.Galeo:BAAANQADCgQIBAABNQADCggICQABAAAAAA==.Gales:BAAANQADCggICQAAAA==.Garfish:BAAANQADCggIDQAAAA==.Garrics:BAAANQADCggIDgAAAA==.Garyndorni:BAAANQADCgYICgAAAA==.Gathaf:BAAANQAECgEIAQAAAA==.',
Ge='Gealtachta:BAAANQAECgEIAQAAAA==.Gebus:BAAANQADCgUICQAAAA==.Geeby:BAAANQADCgcIDgAAAA==.Gelebros:BAAANQADCggIDgAAAA==.Gematrîa:BAAANQAECgYICwAAAA==.Genovevaa:BAAANQADCgcICgAAAA==.Geoffliction:BAAANQADCgEIAQAAAA==.Geöde:BAAANQADCggIDAAAAA==.',
Gh='Ghamma:BAAANQADCgcIBwAAAA==.Ghostops:BAAANQAECgQIBAAAAQ==.',
Gi='Gibberish:BAAANQAECgQIBQAAAA==.Gildàrts:BAAANQADCgUIBQAAAA==.Gilgamush:BAAANQADCgQIBQAAAA==.Gimthal:BAAANQADCgcIBwAAAA==.Ginevra:BAAANQADCgUICQAAAA==.',
Gl='Glacierstorm:BAAANQADCgIIBAAAAA==.Glaivewaifu:BAAANQADCgQIBAAAAA==.Glenvulin:BAAANQADCgYIBgAAAA==.Glorymetcalf:BAAANQADCgUICQAAAA==.',
Go='Gof:BAEANQADCgYIBgABNQADCgcICQABAAAAAA==.Gofsham:BAEANQADCgcICQAAAA==.Golandrith:BAAANQADCgIIBAAAAQ==.Goobertork:BAAANQADCgcICwAAAA==.Gordonramsme:BAAANQADCgcIDAAAAA==.Gorillasdk:BAAANQADCgYICgAAAA==.Gornok:BAAANQADCgYIBgAAAA==.Gothgf:BAAANQADCgIIAgAAAA==.Goturcakes:BAAANQADCgQIBAAAAA==.',
Gr='Grayfawks:BAAANQADCggIDgAAAA==.Graywulf:BAAANQADCggIEQAAAA==.Grazzyazz:BAAANQADCggIDgAAAA==.Greensocks:BAAANQAECgIIAgAAAA==.Greenwarrior:BAAANQADCgEIAQABNQAECgYIEgABAAAAAA==.Grekar:BAAANQADCgQIBAAAAA==.Greynutz:BAAANQADCggIAgAAAA==.Grippisocks:BAAANQAECgUIBwABNQADCggICAABAAAAAA==.Gryffgunner:BAAANQAECgEIAQAAAA==.Græl:BAAANQADCgQIBAAAAA==.',
Gu='Guarok:BAAANQAECgEIAQAAAA==.Gugizimo:BAAANQAECgIIAgAAAA==.Guvante:BAAANQADCgUIBQAAAA==.',
Gw='Gwenavare:BAAANQAECgQIBAAAAA==.',
Ha='Habde:BAAANQADCgIIAgABNQADCgcICgABAAAAAA==.Haise:BAAANQADCgYICwAAAA==.Handpump:BAAANQADCgUICAAAAA==.Hans:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Happyhunting:BAAANQADCggICgAAAA==.Haranasty:BAAANQAECgEIAQAAAA==.Hardasarock:BAAANQAECgUIBQAAAA==.Harrypooty:BAAANQABCgMIAwAAAA==.Harrysnoot:BAAANQABCgQIBQAAAA==.Havsham:BAAANQAECgMIAwAAAA==.Hawa:BAAANQADCgYIBgAAAA==.Hawgcranked:BAAANQADCgYIBgAAAA==.Haydmage:BAAANQADCgYICgAAAA==.',
He='Heartily:BAAANQADCgcIDQAAAA==.Heddurr:BAAANQAECgMIAwAAAA==.Hellguna:BAAANQADCgcIDQAAAA==.Helruner:BAAANQADCgIIAgAAAA==.Heltrskelter:BAAANQADCgYIDAAAAA==.Henbob:BAAANQADCgMIAwAAAA==.Hercdh:BAAANQABCgMIAwAAAA==.Hercion:BAAANQABCgIIAgABNQADCgYIBgABAAAAAA==.Hercmage:BAAANQADCgYIBgAAAA==.Hevelina:BAAANQADCggIDgAAAA==.Hezekiahh:BAAANQADCgcICgAAAA==.',
Hi='Hieroglyphix:BAAANQADCgEIAQAAAA==.Highbeams:BAAANQADCgYIBwAAAA==.',
Ho='Holyinnocent:BAAANQADCgQIBwAAAA==.Honeyrevolvr:BAAANQADCgQIBAAAAA==.Hoobz:BAAANQAECgMIAwAAAA==.Hoser:BAAANQADCgMIAwAAAA==.Hotbunzz:BAAANQADCgIIAgAAAA==.',
Hv='Hvylights:BAAANQAECgUIBgAAAA==.',
Hy='Hydronimbus:BAAANQADCgIIAgAAAA==.Hypershock:BAAANQAECgUIBwAAAA==.',
['Hó']='Hómey:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Hómiee:BAAANQAECgMIBAAAAA==.',
Ic='Iccecycle:BAAANQADCgUIBQAAAA==.Icehopper:BAAANQADCgEIAQAAAA==.',
Id='Idksmthindum:BAAANQAECgQIBAAAAA==.',
Ih='Ihavelust:BAAANQAECgQIBAAAAA==.',
Ik='Ikunoxi:BAAANQAECgMIAwAAAA==.',
Im='Immortalnite:BAAANQAECgUIBgAAAA==.',
In='Incubus:BAAANQABCgIIAgAAAA==.Innerfury:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.Innertempler:BAAANQADCgIIAgABNQADCgYICwABAAAAAA==.Innerthunder:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Insufferable:BAAANQADCgYIBgAAAA==.',
Ir='Ironboar:BAAANQADCgUICAAAAA==.Ironlobster:BAAANQADCgUIBQAAAA==.',
Is='Ishymaell:BAAANQADCggIDAAAAA==.',
Iv='Ivanatrump:BAAANQADCgYIDAAAAA==.',
Iz='Izsún:BAAANQADCgUICQAAAA==.',
Ja='Jadasmith:BAAANQABCgQIBAAAAA==.Jaena:BAAANQADCgUICAAAAA==.Jaggler:BAAANQADCgcIDAAAAA==.Jainá:BAAANQADCgYIBgAAAA==.Jakew:BAAANQAECgEIAgAAAA==.Janceynniela:BAAANQAECgEIAQAAAA==.Janspally:BAAANQADCggIDQAAAA==.Jashe:BAAANQAECgEIAQAAAA==.Jassaene:BAAANQABCgIIAgAAAA==.Jatzartok:BAAANQADCgcIBwAAAA==.Javarielle:BAAANQAECgUIBwAAAA==.Javelina:BAAANQADCgcIDQAAAA==.Jaydemon:BAAANQAECgIIAgAAAA==.Jayrock:BAAANQADCggIDgAAAA==.',
Jb='Jblack:BAAANQADCgYIBgAAAA==.',
Je='Jemm:BAAANQADCgcICgAAAA==.Jeritza:BAAANQADCgMIAwAAAA==.Jeruko:BAAANQAFFAEIAQAAAA==.',
Jh='Jhalori:BAAANQADCgYIBgAAAA==.',
Ji='Jiminycrick:BAAANQAECgIIAgAAAA==.',
Jo='Jonezi:BAAANQAECgQIBQAAAA==.Jothaie:BAAANQADCgUICAAAAA==.',
Jr='Jragonknight:BAAANQADCggIDgAAAA==.',
Ju='Judged:BAAANQADCgUIBwAAAA==.Judgemo:BAAANQAECgQIBAAAAA==.Juggernasty:BAAANQADCgQIBAAAAA==.Jumpnjak:BAAANQAECggIAwAAAA==.Jumpy:BAAANQADCggICQAAAA==.Justdax:BAAANQAECgEIAQAAAA==.Justthetips:BAAANQADCgUICAAAAA==.',
['Jø']='Jønø:BAAANQAECgIIAgAAAA==.',
Ka='Kaast:BAAANQAECgQIBAAAAA==.Kaddee:BAAANQADCgYICQAAAA==.Kaelin:BAAANQADCgUIBQAAAA==.Kaemra:BAAANQAECgEIAQAAAA==.Kahto:BAAANQADCgUIBwAAAA==.Kaialandre:BAAANQAECgUIBgAAAA==.Kajri:BAAANQADCgQIBAAAAA==.Kalenian:BAAANQAECgMIAwAAAA==.Kalldin:BAAANQAECgEIAQAAAA==.Kalubew:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.Kalîente:BAAANQAECgIIAgAAAA==.Kaprah:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Karal:BAAANQADCgUICAAAAA==.Karinfromhr:BAAANQABCgIIAgAAAA==.Karrowin:BAAANQADCgUIBQAAAA==.Karzon:BAAANQADCgcIDAAAAA==.Katamoria:BAAANQADCggIDwAAAA==.Katarìe:BAAANQADCggIDgAAAA==.Katsara:BAAANQAECgIIAgAAAA==.Kavaax:BAAANQAECgQIBAAAAA==.Kaydence:BAAANQAECgEIAQAAAA==.Kaydiah:BAAANQADCggIDwAAAA==.Kayllia:BAAANQADCgIIAgAAAA==.',
Ke='Keenaxe:BAAANQAECgEIAQAAAA==.Keggiesmalls:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Keldorn:BAAANQADCggIDgAAAA==.Kelthear:BAAANQAECgIIAgAAAA==.Kelína:BAAANQADCggIDgAAAA==.Kenrato:BAAANQADCggIDwAAAA==.Kensen:BAAANQADCgYIDAAAAA==.Kerianassa:BAAANQADCgQIBAAAAA==.',
Kh='Khalais:BAAANQADCgcIBwAAAA==.Kharalla:BAAANQAECgIIAgAAAA==.Khorhil:BAAANQADCgYIBgAAAA==.',
Ki='Kiki:BAAANQADCgcICQAAAA==.Kilhara:BAAANQAECgEIAQAAAA==.Killerthighs:BAAANQADCgIIAgAAAA==.Kinadin:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Kinegos:BAAANQAECgEIAQAAAA==.Kirint:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.',
Kn='Knarlee:BAAANQADCggIDgAAAA==.Knob:BAAANQAECgUIBgAAAA==.Knockd:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Knockz:BAAANQAECgIIAgAAAA==.',
Ko='Kobask:BAAANQADCgIIAgAAAA==.Konvicktion:BAAANQADCggICAAAAA==.',
Kr='Kratoast:BAAANQADCgMIAwAAAA==.Kraytous:BAAANQAECgUIBgAAAA==.Kregon:BAAANQADCggIEAAAAA==.Kretolo:BAAANQADCggICQAAAA==.Kribage:BAAANQADCggICQAAAA==.Krozard:BAAANQAECgIIAgAAAA==.Kríelle:BAAANQAECgUIBwAAAA==.',
Ku='Kuinshie:BAAANQADCgIIBAABNQADCgMIAwABAAAAAA==.',
Ky='Kyr:BAAANQADCgYIEQAAAA==.Kyra:BAAANQADCgYICQAAAA==.Kyriélle:BAAANQAECgIIAgAAAA==.',
['Kà']='Kài:BAAANQADCgMIAwAAAA==.',
La='Laeara:BAAANQAECgIIAgABNQADCgUICAABAAAAAA==.Lamantee:BAAANQABCgIIBAAAAA==.Lanaera:BAAANQADCgEIAQAAAA==.Laneer:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Lannivath:BAAANQADCgcICgAAAA==.Larah:BAAANQADCgIIAgAAAA==.Lavabêard:BAAANQADCgcIBwAAAA==.Lawnart:BAAANQADCgIIAgAAAA==.Laxus:BAAANQADCgYICQAAAA==.',
Le='Leliot:BAAANQAECgEIAgAAAA==.Leona:BAAANQADCggIDAAAAA==.',
Li='Licestr:BAAANQADCgcIDQAAAA==.Lichmyshot:BAAANQAECgEIAQAAAA==.Lightdmg:BAAANQADCgIIAgAAAA==.Lightguy:BAAANQAECgIIAgAAAA==.Lightma:BAAANQAECgMIBAABNQAECgIIAwABAAAAAA==.Lilaitria:BAAANQADCgIIAgABNQADCggIDwABAAAAAA==.Liliybug:BAAANQADCgYICQAAAA==.Lilpandibr:BAAANQADCgcICwAAAA==.Lilyroses:BAAANQADCgYICwAAAA==.Linash:BAAANQADCgYIBgAAAA==.Linsin:BAAANQADCggIDgAAAA==.Littlesun:BAAANQADCgQIBAAAAA==.Lizardlick:BAAANQADCgYIBgAAAA==.',
Ll='Llamaknight:BAAANQAECgUIBwAAAA==.',
Lo='Lockdark:BAAANQADCgEIAQAAAA==.Lockedout:BAAANQADCggICAAAAA==.Lockjom:BAAANQAECgEIAQAAAA==.Locutie:BAAANQADCgYICwAAAA==.Lokrah:BAAANQADCgYIBgAAAA==.Lost:BAAANQADCggIDgAAAA==.Lostson:BAAANQADCgQIBAAAAA==.Loveliness:BAAANQABCgQIBAAAAA==.Loviatar:BAAANQAECgIIAgAAAA==.Loviro:BAAANQAECgIIAgAAAA==.',
Lu='Lucinus:BAAANQADCgYIBgAAAA==.Lunahuntress:BAAANQADCgUIBQAAAA==.Lusty:BAAANQADCgQIBAAAAA==.Luxferus:BAAANQAECgMIBAAAAA==.Luxzilla:BAAANQABCgMIAgAAAA==.',
Ly='Lyanara:BAAANQAECgQIBAAAAA==.Lyican:BAAANQAECgIIAgAAAA==.Lyndsay:BAAANQADCgcIDAAAAA==.',
Ma='Macroo:BAAANQADCgEIAQAAAA==.Madamkitty:BAAANQADCgYICwAAAA==.Madmat:BAAANQADCgMIAwAAAA==.Maekaros:BAAANQADCgEIAQAAAA==.Maeliora:BAAANQADCgUIBQAAAA==.Maenix:BAAANQADCgQIBAAAAA==.Magarithas:BAAANQAECgUIBgAAAA==.Magdie:BAAANQAECgQIBAAAAA==.Magicdevil:BAAANQADCgUIBQAAAA==.Magicundies:BAAANQADCgQIBAAAAA==.Magikz:BAAANQADCgUIBgAAAA==.Maginitis:BAAANQAECgQIBAAAAA==.Magsissippi:BAAANQADCgYIBgAAAA==.Mahoragah:BAAANQADCgUICQAAAA==.Mahune:BAAANQADCggICwAAAA==.Malacanth:BAAANQADCgYICQAAAA==.Malfuria:BAAANQADCgYIDAAAAA==.Maltorias:BAAANQADCggICAAAAA==.Mammamilker:BAAANQADCgQIBAAAAA==.Managed:BAAANQADCgYIDgAAAA==.Mandroes:BAAANQADCgQIBAAAAA==.Manga:BAAANQADCgcIBwAAAA==.Mannheim:BAAANQADCgcIDAAAAA==.Mannydamanly:BAAANQADCgcICwAAAA==.Manwei:BAAANQADCgQIBAAAAA==.Mapes:BAAANQADCgEIAQAAAA==.Mapleoats:BAAANQADCgYIBgAAAA==.Maplepally:BAAANQAECgEIAQAAAA==.Mardel:BAAANQAECgUICQAAAA==.Markymeta:BAAANQAECgEIAQAAAA==.Martyrdom:BAAANQAECgQIBQAAAA==.Marék:BAAANQADCgQIBAAAAA==.Masubi:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Mathilda:BAAANQADCgEIAQAAAA==.Mattdh:BAAANQAECgUIBgABNQAECgYIEgABAAAAAA==.Mayjah:BAAANQAECgUIBwAAAA==.Mazzorz:BAAANQADCgQIBAAAAA==.',
Mc='Mcscooterson:BAAANQADCggIDwAAAA==.',
Me='Mechegidius:BAAANQAECgEIAQAAAA==.Meenja:BAAANQAECgMIBAAAAA==.Meeseomelete:BAAANQADCgYICQAAAA==.Mekademuerte:BAAANQADCgYICgAAAA==.Melady:BAAANQADCggIDgAAAA==.Melisity:BAAANQADCggIDwAAAA==.Mellamoalex:BAAANQABCgQIAwAAAA==.Melïnoe:BAAANQADCgMIAwAAAA==.Menamaga:BAAANQADCgQICAAAAA==.Mentycles:BAAANQADCggIDgAAAA==.Mercedis:BAAANQAECgQIBwAAAA==.Merydeath:BAAANQADCgIIAwAAAA==.',
Mi='Mids:BAAANQADCgYICwAAAA==.Mihira:BAAANQAECgIIAgAAAA==.Miinii:BAAANQADCgUIBQAAAA==.Mintweaver:BAAANQADCgYIBgAAAA==.Misereatur:BAAANQABCgQIBQAAAA==.Mistaaytch:BAAANQADCgcICQAAAA==.Mistika:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Mithrandyr:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.Mitigates:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.',
Mn='Mnimi:BAAANQAECgEIAQAAAA==.',
Mo='Monkeballs:BAAANQAFFAEIAQAAAA==.Monkâs:BAAANQAECgMIBAAAAA==.Monstacardo:BAAANQAECgQIBAAAAA==.Mooncaliber:BAAANQAECgEIAQAAAA==.Moondrala:BAAANQAECgMIBAAAAA==.Moonyy:BAAANQADCgQIBAAAAA==.Mootodeath:BAAANQADCgIIAgAAAA==.Mordsîth:BAAANQADCgcIDQAAAA==.Morgona:BAAANQADCgIIAwAAAA==.Morrin:BAAANQADCggIDgAAAA==.Moîraine:BAAANQAECgEIAQAAAA==.',
Mu='Mudslide:BAAANQADCgYIDQAAAA==.Mulciber:BAAANQADCggIDwAAAA==.Mulsi:BAAANQADCgMIAwAAAA==.Muralin:BAAANQADCgEIAQAAAA==.',
My='Myrian:BAAANQAECgEIAgAAAA==.Mysticalmoon:BAAANQADCgMIAwAAAA==.',
['Mö']='Möösê:BAAANQADCggIDgAAAA==.',
Na='Nagafurry:BAAANQADCgYICwAAAA==.Nahadoth:BAAANQAECgIIAgAAAA==.Nahas:BAAANQAECgEIAQAAAA==.Nahtee:BAAANQADCggIDQAAAA==.Naib:BAAANQADCgQIBQAAAA==.Nalaa:BAAANQADCgYIBgAAAA==.Namrathor:BAAANQADCgQIBAABNQADCgcICAABAAAAAA==.Namruh:BAAANQADCgcICAAAAA==.Nannydanny:BAAANQAECgEIAQAAAA==.Napless:BAAANQADCgUIBQAAAA==.Narivi:BAAANQAECgEIAQAAAA==.Nathrissa:BAAANQAECgIIAgAAAA==.Natsunoki:BAAANQAECgUIBwAAAA==.Nayati:BAAANQADCgMIAwAAAA==.',
Ne='Neddludd:BAAANQADCggIDQAAAA==.Nelvari:BAAANQADCggIDwAAAA==.Nennya:BAAANQADCggIDQAAAA==.Neox:BAAANQADCgIIBAAAAA==.Neredonte:BAAANQADCggICAAAAA==.Nevixia:BAAANQAECgEIAQAAAA==.Newc:BAAANQADCgcICQAAAA==.Neò:BAAANQADCgUICgAAAA==.',
Ni='Niallad:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Niaorud:BAAANQADCggICAAAAA==.Nighthood:BAAANQADCgcIDQAAAA==.Nightmanimal:BAAANQADCgcIDAABNQADCggIDgABAAAAAA==.Nigth:BAAANQAECgEIAQAAAA==.Nihm:BAAANQAECgMIAwAAAA==.Nikonrage:BAAANQADCggIDwAAAA==.Nilofur:BAAANQADCgcIBwAAAA==.Nimarai:BAAANQADCggIDwAAAA==.Nimbus:BAAANQADCgEIAQAAAA==.Nimrodton:BAAANQADCgcICgAAAA==.Nixxiie:BAAANQAECgEIAQAAAA==.',
No='Noellexd:BAAANQAECgIIAgAAAA==.Nomamor:BAAANQADCggICQAAAA==.Noobadin:BAAANQADCgQIBAAAAA==.Normund:BAAANQADCggIDgAAAA==.Noveria:BAAANQAECgIIAgAAAA==.',
Nu='Nuadore:BAAANQADCgcIDQAAAA==.Nuca:BAAANQADCgQIBAAAAA==.Nuwien:BAAANQAECgQIBAAAAA==.',
Nv='Nvme:BAAANQAECgIIAgAAAA==.',
Ny='Nyneave:BAAANQAECgEIAQAAAA==.',
['Nè']='Nèo:BAAANQAECgQIBQAAAA==.',
Ob='Oberok:BAAANQADCgcIDQAAAA==.',
Oc='Ocklayn:BAAANQAECgQIBAAAAA==.',
Og='Ogerslayer:BAAANQADCgMIAwAAAA==.Ogproduct:BAAANQAECgEIAQAAAA==.',
Oh='Ohhbiscuits:BAAANQABCgQIAgAAAA==.',
Ok='Okashå:BAAANQADCggICAAAAA==.',
Ol='Oleandar:BAAANQAECgIIAgAAAA==.Ollathir:BAAANQADCgQIBAAAAA==.Olrox:BAAANQADCgQIBgAAAA==.',
Om='Omeguiz:BAAANQADCggIDgAAAA==.Omni:BAAANQADCggIDAAAAA==.',
On='Onceapun:BAAANQADCgIIAgAAAA==.Oneunder:BAAANQADCgQIBQAAAA==.',
Op='Opa:BAAANQAECgUICQAAAA==.Opalore:BAAANQADCggIDgAAAA==.Oppawinfury:BAAANQAECgUIBwAAAA==.Opportunist:BAAANQADCggIDgAAAA==.Oppydono:BAAANQAECgUIBwAAAA==.',
Or='Orejon:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Oryo:BAAANQADCgcIDQABNQAECgUICgABAAAAAA==.',
Os='Oshrom:BAAANQADCgYIDAAAAA==.',
Pa='Paako:BAAANQABCgIIAgAAAA==.Packapunch:BAAANQADCgYIBgAAAA==.Padrebear:BAAANQADCggIDgAAAA==.Pakanokis:BAAANQAECgIIAgAAAA==.Palchodie:BAAANQADCgYIBwAAAA==.Pallywhackit:BAAANQADCgcICwAAAA==.Pancho:BAAANQAECgcIDAAAAA==.Panchodk:BAAANQADCgQIBAAAAA==.Panchoxd:BAAANQAECgIIAwAAAA==.Pandemoniuxs:BAAANQAECgIIAgAAAA==.Pandomedic:BAEANQADCgcIDQABNQAECgEIAQABAAAAAA==.Pangon:BAAANQADCggIDAAAAA==.Panzerfauste:BAAANQADCggIDgAAAA==.Paos:BAAANQAECgIIAgAAAA==.Paragøn:BAAANQADCgEIAgABNQADCggIDwABAAAAAA==.Paratheius:BAAANQADCggIDwAAAA==.Partz:BAAANQAECgIIAgAAAA==.Patrissia:BAAANQADCgYIBgAAAA==.Pauhunt:BAAANQADCgQIBAAAAA==.',
Pe='Pelleus:BAAANQAECgEIAQAAAA==.Pelzel:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Perdluz:BAAANQAECgIIAgAAAA==.Peuf:BAAANQADCgQIBAAAAA==.',
Ph='Philthy:BAAANQADCggIDwAAAA==.',
Pi='Pics:BAAANQAECgQIBAAAAA==.Piiff:BAAANQADCgcIBwAAAA==.Piment:BAAANQADCgQIBAAAAA==.Pistóph:BAAANQADCgEIAQAAAA==.Pixiepops:BAAANQADCgQIBwAAAA==.Pizzadahutt:BAAANQAECgIIAwAAAA==.',
Pl='Plstt:BAAANQADCggIDwAAAA==.Plumita:BAAANQADCgIIAgAAAA==.',
Po='Pokemeplease:BAAANQAECgcICgAAAA==.Policebus:BAAANQADCgcIDAAAAA==.Pontos:BAAANQADCgQIBAAAAA==.Pooballs:BAAANQADCgMIBQAAAA==.Postmortemx:BAAANQAECgQIBQAAAA==.Potytrained:BAAANQADCgMIAwAAAA==.Pouncington:BAAANQADCgEIAQABNQAECgYIEgABAAAAAA==.Powerbun:BAAANQADCgYIBgAAAA==.',
Pp='Pp:BAAANQAECgEIAQAAAA==.',
Pr='Praevalens:BAAANQADCgYICAAAAA==.Prayerbender:BAAANQAECgMIAwAAAA==.Prevokdsaint:BAAANQAECgYICAAAAA==.Primelus:BAAANQADCggIDgAAAA==.',
Ps='Pspspspsps:BAAANQAECgIIAgAAAA==.',
Pu='Pumpi:BAAANQAECgEIAQAAAA==.Purkmcclappy:BAAANQAECgQIBAAAAA==.',
Pw='Pwippin:BAAANQADCgQIBAABNQADCgcICgABAAAAAA==.',
Py='Pyromarine:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Pyrräh:BAAANQADCgUIBQAAAA==.',
['Pà']='Pàìn:BAAANQAECgEIAQAAAA==.',
['Pé']='Pétmaster:BAAANQADCgUICQAAAA==.',
['Pù']='Pùff:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Qu='Quactemoc:BAAANQAECgIIAgAAAA==.Queditate:BAAANQAECgEIAQAAAA==.Queragon:BAAANQADCgYICAAAAA==.Quickie:BAAANQADCggIDwAAAA==.Quintom:BAAANQABCgMIAgAAAA==.',
Qw='Qwallin:BAAANQADCgQIBgAAAA==.Qweb:BAAANQADCgUIBQAAAA==.',
Ra='Raboge:BAEANQADCgYICwAAAA==.Racarris:BAAANQADCgQIBAAAAA==.Rachelreano:BAAANQAECgEIAQAAAA==.Raevive:BAAANQAECgQIBAAAAA==.Raeyne:BAAANQADCggIDgAAAA==.Rajus:BAAANQADCgIIBAAAAA==.Rakoten:BAAANQADCgIIAgAAAA==.Rallös:BAAANQAECgYICQAAAA==.Raltan:BAAANQADCggIDgAAAA==.Ramberth:BAAANQAECgEIAQAAAA==.Ramgorb:BAAANQADCgYIDAAAAA==.Randomdots:BAAANQADCgYIBgAAAA==.Randomhunt:BAAANQAECgQIBwAAAA==.Randomlock:BAAANQAECgIIBAAAAA==.Rapidcurse:BAAANQADCgUIBQAAAA==.Rathalos:BAAANQADCgcICQAAAA==.Rathma:BAAANQAECgQIBwABNQAECgYIDQABAAAAAA==.Ratyeeter:BAAANQAECgIIAgAAAA==.Ravarim:BAAANQADCgYICQABNQADCggIEAABAAAAAA==.Raveen:BAAANQABCgIIBAAAAA==.Ravesorc:BAAANQADCgcICAAAAA==.Razmitaz:BAAANQAECgIIAgAAAA==.Razoir:BAAANQADCgUIBQAAAA==.Razz:BAAANQADCgQIBAAAAA==.',
Re='Realdeathtyr:BAAANQADCggIDgAAAA==.Recherché:BAAANQADCggICgAAAA==.Redandginger:BAAANQADCgIIBAAAAA==.Redneb:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Reigndrops:BAAANQADCgYICwAAAA==.Reinay:BAAANQADCgMIAwAAAA==.Reindeerr:BAAANQAECgMIAwAAAA==.Reiyo:BAAANQADCgIIBAAAAA==.Relikar:BAAANQAECgEIAQAAAA==.Relsafk:BAAANQADCgcIBwABNQAECgQIBQABAAAAAA==.Reminsheal:BAAANQAECgYIBgAAAA==.Resmè:BAAANQADCgcIDAAAAA==.Retx:BAAANQADCgQIBAAAAA==.Revelia:BAAANQADCggIDwAAAA==.Revenger:BAAANQADCggICAAAAA==.Revenwind:BAAANQADCgYICgAAAA==.Revw:BAAANQAECgEIAQAAAA==.Reíka:BAAANQADCgcIDAAAAA==.',
Rh='Rhastia:BAAANQADCggICQAAAA==.Rhynoz:BAAANQAECgYIBgAAAA==.Rhäne:BAAANQADCgcICQAAAA==.',
Ri='Rifflizard:BAAANQADCggIDwAAAA==.Riga:BAAANQADCggIDgAAAA==.Righteöus:BAAANQADCgEIAQAAAA==.Rinleigh:BAAANQAECgEIAQAAAA==.Rista:BAAANQAECgIIAgAAAA==.Rizah:BAAANQADCgYICwABNQADCggIEAABAAAAAA==.',
Ro='Robindebrave:BAAANQADCggIDgAAAA==.Roion:BAAANQADCgcICgAAAA==.Roks:BAAANQADCggIEAABNQAECgEIAQABAAAAAA==.Ronor:BAAANQABCgIIAgAAAA==.Rorlath:BAAANQADCggIDwAAAA==.Rosablade:BAAANQABCgQIBgAAAA==.Rotbreath:BAAANQAECgMIAwAAAA==.Rotknees:BAAANQADCgYIDAAAAA==.Roxxùs:BAAANQAECgQIBAAAAA==.',
Ru='Ruiinaxx:BAAANQADCgMIAwAAAA==.Runehelm:BAAANQADCgUIBQAAAA==.Runningamonk:BAAANQADCggICAAAAA==.Rupaull:BAAANQADCgcICgAAAA==.Ruruk:BAAANQADCgcIDQAAAA==.Ruthlessly:BAAANQAECgIIAgAAAA==.',
Rw='Rwby:BAAANQAECgIIAgAAAA==.',
Ry='Rydrion:BAAANQAECgEIAQAAAA==.Rykah:BAAANQADCggIDgAAAA==.Ryndasa:BAAANQADCggIDgAAAA==.Rynnifer:BAAANQAECgQIBAAAAA==.Ryshot:BAAANQADCgYICAAAAA==.Ryúk:BAAANQADCgUIBQAAAA==.',
['Rà']='Ràyne:BAAANQADCggICQAAAA==.',
['Ré']='Répent:BAAANQAECgIIAgAAAA==.',
Sa='Sabbie:BAAANQAFFAIIAgAAAA==.Sabrael:BAAANQAECgIIAgAAAA==.Sabryelle:BAAANQADCgQIBAAAAA==.Sadburrito:BAAANQADCgYICQAAAA==.Saddiel:BAAANQADCggIDQAAAA==.Saer:BAAANQAECgIIAgAAAA==.Saevromauch:BAAANQADCgcICAAAAA==.Sageoffan:BAEANQAECgQIBAAAAA==.Sajah:BAAANQADCgYICgAAAA==.Salenastus:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Sallylock:BAAANQADCgMIAwAAAA==.Salvatiion:BAAANQADCgYICgAAAA==.Samareith:BAAANQADCgYICwABNQAECgIIAgABAAAAAA==.Samberg:BAAANQAECgQIBAAAAA==.Sandstalker:BAAANQAECgUIBgAAAA==.Sangwhen:BAAANQADCgIIAgAAAA==.Saphyria:BAAANQADCggIDgAAAA==.Saraplegic:BAAANQADCggICwAAAA==.Sareene:BAAANQAECgIIAgAAAA==.Sarraah:BAAANQADCgcIDAAAAA==.Saturnia:BAAANQADCgYICwAAAA==.Savannay:BAAANQAECgIIAwAAAA==.Saül:BAAANQADCgUIBQAAAA==.',
Sb='Sbjarl:BAAANQADCgMIAwAAAA==.',
Sc='Schnozz:BAAANQAECgUIBwAAAA==.Schnozzdruid:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Scry:BAAANQAECgEIAQAAAA==.',
Se='Searenity:BAAANQAECgQIBAAAAA==.Sefiron:BAAANQADCggIDwAAAA==.Sejam:BAAANQADCgIIAgAAAA==.Sejeong:BAAANQADCgEIAQABNQADCgYIDAABAAAAAA==.Semmiramis:BAAANQAECgcIDAAAAA==.Seria:BAAANQAECgEIAQAAAA==.Severus:BAAANQAECgIIAgAAAA==.Señorass:BAAANQADCgYIBgAAAA==.',
Sh='Shadowone:BAAANQADCgEIAwAAAA==.Shadowswîper:BAAANQADCggICAAAAA==.Shadowthrone:BAAANQADCgUICQAAAA==.Shakavoodoo:BAAANQABCgMIAwAAAA==.Shamage:BAAANQAECgMIAwAAAA==.Shamette:BAAANQADCgcIDAAAAA==.Shamwise:BAAANQADCgcICgAAAA==.Shannongram:BAAANQADCgYIBgAAAA==.Shard:BAAANQADCgYIBgAAAA==.Shardmist:BAAANQADCgIIAgAAAA==.Sharese:BAAANQADCggICAAAAA==.Shashara:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.Shawtyblastn:BAAANQADCgIIAgAAAA==.Shayla:BAAANQADCggIDwAAAA==.Shaî:BAEANQADCggIDgAAAA==.Shellager:BAAANQADCgYICgAAAA==.Shenrón:BAAANQADCgIIAgAAAA==.Shicon:BAAANQADCgQIBAABNQADCgcICAABAAAAAA==.Shinhann:BAAANQADCgMIBQAAAA==.Shinigämï:BAAANQAECgEIAQAAAA==.Shinlong:BAAANQADCgMIAwAAAA==.Shinochu:BAAANQADCggICAAAAA==.Shkwippin:BAAANQADCgcICgAAAA==.Shockon:BAAANQADCggIDgAAAQ==.Shortkeg:BAAANQADCggICAABNQAECgUICgABAAAAAA==.Shotelemento:BAAANQAECgEIAQAAAA==.Shotstuff:BAAANQAECgMIBAAAAA==.Shredders:BAAANQAECgQIBQAAAA==.Shrug:BAAANQADCgMIAwAAAA==.Shutup:BAAANQADCggIEAAAAA==.',
Si='Siegmeyer:BAAANQADCgEIAQAAAA==.Silverembers:BAAANQAECgEIAQAAAA==.Silverskin:BAAANQADCggIDAAAAA==.Silverstryke:BAAANQADCggIDgAAAA==.Sinndelle:BAAANQADCgQIBAAAAA==.Sithic:BAAANQAECggIAgAAAA==.Sithmagic:BAAANQADCggICAAAAA==.',
Sk='Skillasaurus:BAAANQAECgQIBQAAAA==.Skitaepo:BAAANQAECgQIBAAAAA==.Skoalstrait:BAAANQADCgIIAgAAAA==.Skou:BAAANQAECgUIBgAAAA==.Skozer:BAAANQADCgUIBQAAAA==.Skycaptaín:BAAANQAECgMIBAAAAA==.Skúld:BAAANQADCgQIBAAAAA==.',
Sl='Slapntickles:BAAANQAECgEIAQAAAA==.Slayy:BAAANQADCggIDwAAAA==.Sleepies:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Sm='Smacks:BAAANQADCgUIBQAAAA==.Smallarcana:BAAANQAECgEIAQAAAA==.Smashy:BAAANQADCggIDgAAAA==.Smea:BAAANQADCggIDgAAAA==.Smenalpha:BAAANQADCgMIAwAAAA==.Smhlol:BAAANQAECgEIAgAAAA==.Smoothblade:BAAANQADCggIDgAAAA==.',
Sn='Sniffany:BAAANQADCgEIAQAAAA==.',
So='Sofiel:BAAANQADCggIDwAAAA==.Solae:BAAANQADCgcIBwAAAA==.Sorbanos:BAAANQADCgMIAwAAAA==.Sorlon:BAAANQADCgMIAwAAAA==.Sosmor:BAAANQADCgYICQAAAA==.Souldevil:BAAANQADCgUIBwABNQAECgIIAgABAAAAAA==.Soullessw:BAAANQADCgUICAAAAA==.Soulweave:BAAANQAECgIIAgAAAA==.',
Sp='Sparkiie:BAAANQADCgEIAQAAAA==.Sparklehands:BAAANQAECgEIAQAAAA==.Sparklezs:BAAANQADCgYICwAAAA==.Specterdh:BAAANQAECgEIAQAAAA==.Spitty:BAAANQADCgcIDAAAAA==.Spooky:BAAANQADCgEIAQAAAA==.Spoonfeed:BAAANQAECgMIBAAAAA==.Sputtin:BAAANQAECgQIBAAAAA==.',
St='Stabbyshadow:BAAANQADCgQIBAAAAA==.Stabbyspydr:BAAANQADCgYICQAAAA==.Stackz:BAAANQAECgUIBQAAAA==.Starbreakêr:BAAANQADCgEIAQAAAA==.Starbun:BAAANQAECgEIAQAAAA==.Staszia:BAAANQADCgQIBAAAAA==.Steeleyé:BAAANQADCggICAAAAA==.Stellarosa:BAAANQADCggIDgAAAA==.Stemihunter:BAEANQAECgEIAQAAAA==.Stemislayer:BAEANQADCgYIBgABNQAECgEIAQABAAAAAA==.Stepdrasta:BAAANQADCggIDgAAAA==.Stepstone:BAAANQADCgUIBwAAAA==.Stonedove:BAAANQADCgUIBQAAAA==.Stonemonk:BAAANQADCggICAAAAA==.Stonewalljay:BAAANQADCgcIDQAAAA==.Stont:BAAANQADCgEIAQAAAA==.Stormienite:BAAANQADCgUIBQABNQAECgUIBgABAAAAAA==.Strikeback:BAAANQADCgUIBQAAAA==.Strzyga:BAEANQAECgQIBQAAAA==.Sttygian:BAAANQAECgIIAgAAAA==.',
Su='Subbywubby:BAAANQADCgYICQAAAA==.Submissa:BAAANQADCgYIBgAAAA==.Subtleshrike:BAAANQAECgEIAgAAAA==.Sugar:BAAANQAECgIIAgAAAA==.Sumalaht:BAAANQADCgEIAQAAAA==.Supliciel:BAAANQAECgMIAwAAAA==.Supremus:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Sutolshirak:BAAANQADCgQIBQAAAA==.',
Sw='Switchyy:BAAANQADCgUICAAAAA==.',
Sy='Sydthesquid:BAAANQADCgEIAQAAAA==.Sylerria:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.Sylvanir:BAAANQADCgQIBAAAAA==.Sylviefae:BAAANQADCgIIAgAAAA==.',
['Sá']='Sátan:BAAANQADCgEIAQAAAA==.',
['Sé']='Sévén:BAAANQADCggIDgAAAA==.',
['Sö']='Sölburn:BAAANQADCgQIBwAAAA==.',
Ta='Tachislock:BAAANQADCgYICAAAAA==.Tacosbringer:BAAANQAECgUIBgAAAA==.Taleen:BAAANQADCgMIAwAAAA==.Tallyri:BAAANQABCgMIAwAAAA==.Talven:BAAANQADCgUICgAAAA==.Talyanna:BAAANQADCgUIBQAAAA==.Tankomatic:BAAANQAECgEIAQAAAA==.Tanksnspanks:BAAANQADCgIIAgAAAA==.Tassy:BAAANQADCgUIBQAAAA==.Tavick:BAAANQADCggICQAAAA==.',
Te='Teddyboy:BAAANQADCgYIDAAAAA==.Teenis:BAAANQADCgYICwAAAA==.Tehdeath:BAAANQADCggIDgAAAA==.Teiela:BAAANQADCgUIBQAAAA==.Tekin:BAAANQADCggIDgAAAA==.Tenyris:BAAANQAECgQIBAAAAA==.Teslinna:BAAANQADCgcICgAAAA==.Testackles:BAAANQAECgUIBQAAAA==.',
Tf='Tft:BAAANQADCggICgABNQAECggIDgABAAAAAA==.Tftmonk:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.',
Th='Thadorblor:BAAANQADCgIIBAAAAA==.Thaghuen:BAAANQADCggIEAAAAA==.Thanazudon:BAAANQAECgUIBQAAAA==.Thardras:BAAANQADCggIDgAAAA==.Thatbish:BAAANQABCgQIBgAAAA==.Thauria:BAAANQADCgUICQAAAA==.Theantilynd:BAAANQAECgQIBAAAAA==.Thedh:BAAANQADCgYIBgAAAA==.Thelegendary:BAAANQAECgYICgAAAA==.Themoofather:BAAANQADCgIIAgAAAA==.Thenära:BAAANQAECgQIBQAAAA==.Thorakor:BAAANQADCggICAAAAA==.Thorgrihm:BAEANQADCgYICwAAAA==.Thoriden:BAAANQADCgcICgAAAA==.Threslor:BAEBNQAECoEXAAICAAkJTx/+AgBDAwACAAkJTx/+AgBDAwAAAA==.Thul:BAAANQADCgYIBgAAAA==.Thundaira:BAAANQADCgEIAQAAAA==.Thunderkong:BAAANQADCgEIAQAAAA==.Thurbin:BAAANQADCgEIAQAAAA==.Thurrin:BAAANQAECgIIAgAAAA==.Thysdom:BAAANQADCgYIBgAAAA==.',
Ti='Tiancesham:BAAANQADCgcICgAAAA==.Tieza:BAAANQADCgEIAQAAAA==.Tiik:BAAANQADCggIDgAAAA==.Tiktokboom:BAAANQADCgYICQAAAA==.Timebendr:BAAANQADCgUICAAAAA==.Tingles:BAAANQADCgEIAQAAAA==.Tinybop:BAAANQADCgQIBAAAAA==.Tipsei:BAAANQADCggICwAAAA==.Tipster:BAAANQADCgMIAwABNQADCggICwABAAAAAA==.Tiryns:BAAANQADCggICAAAAA==.Titantenai:BAAANQAECgMIBAAAAA==.',
To='Toasttyy:BAAANQAECgIIAgAAAA==.Tombelaine:BAAANQADCgYICwAAAA==.Tomolak:BAAANQADCgcICwAAAA==.Toolara:BAAANQAECgEIAQAAAA==.Torrential:BAAANQAECgUIBQAAAA==.Tortelliní:BAAANQADCgYICgAAAA==.Totemlucky:BAAANQABCgEIAQAAAA==.Totsmagoats:BAAANQAECgIIAgAAAA==.',
Tp='Tpax:BAAANQAECgIIAgAAAA==.',
Tr='Tralanaz:BAAANQADCgUIBQAAAA==.Traler:BAAANQAECgEIAQAAAA==.Tribrid:BAAANQAECgIIAgAAAA==.Tripee:BAAANQADCgYIDAAAAA==.Trolan:BAAANQADCgQIBAAAAA==.Truchas:BAAANQADCgQIBQAAAA==.Trugwa:BAAANQADCgQIBAAAAA==.Trunksjunkie:BAAANQADCgUICQAAAA==.Tràse:BAAANQADCgUIBQAAAA==.Trälér:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Tu='Tui:BAAANQAECgEIAQAAAA==.Turboignis:BAAANQADCgUICQAAAA==.',
Ty='Tychira:BAAANQADCggICAABNQAECgUIBgABAAAAAA==.Tylor:BAAANQADCgYIBwAAAA==.Tyrannicãl:BAAANQAECgEIAQAAAA==.Tyrhonda:BAAANQADCgUIBgAAAA==.',
['Tò']='Tòy:BAAANQAECgcIDAAAAA==.',
Uc='Uchawi:BAAANQADCggIDgAAAA==.',
Ud='Udriel:BAAANQAECgQIBwAAAA==.',
Ug='Ugtana:BAAANQADCgQIBQAAAA==.',
Uh='Uhohbehindu:BAAANQADCgYICwAAAA==.Uhrich:BAAANQAECgMIBAAAAA==.',
Ul='Ulithes:BAAANQADCgEIAQAAAA==.Ulruk:BAAANQADCgYICwAAAA==.',
Um='Umtra:BAAANQADCggIDwAAAA==.',
Ur='Ursinlock:BAAANQADCgcIDAAAAA==.',
Us='Usedtobe:BAAANQABCgEIAQAAAA==.',
Uw='Uwukong:BAAANQADCgQIBAAAAA==.',
Va='Vaguard:BAAANQADCgcIBwAAAA==.Valadriel:BAAANQADCgUICQAAAA==.Valarundkil:BAAANQAECgMIAwAAAA==.Valrion:BAAANQADCgUIBQAAAA==.Vampcorpse:BAAANQADCgYICAAAAA==.Vanastara:BAAANQADCggIDgAAAA==.Vanimar:BAAANQAECgIIAgAAAA==.Vanthrain:BAAANQADCgYICwAAAA==.',
Ve='Velashar:BAAANQADCggIDgAAAA==.Veleina:BAAANQADCgcIBwAAAA==.Veletari:BAAANQAECgEIAQAAAA==.Veliinna:BAAANQADCggIDwAAAA==.Venkukrugar:BAAANQADCggIDgAAAA==.Venndia:BAAANQADCgQIBAAAAA==.Vergie:BAAANQAECgUIBwAAAA==.Verraden:BAAANQADCgQIBAAAAA==.Verritas:BAAANQADCgUIBwAAAA==.Versiana:BAAANQADCgcIDQABNQADCgcIDQABAAAAAA==.Vesperly:BAAANQADCggIDgAAAA==.Vesso:BAAANQAECgMIAwAAAA==.Vexxn:BAAANQADCgcIDAAAAA==.',
Vi='Villis:BAAANQADCggIDwAAAA==.Vintrador:BAAANQADCggIDgAAAA==.Visike:BAAANQADCgIIAgAAAA==.Vixson:BAAANQADCgQIBAAAAA==.',
Vo='Voidla:BAAANQADCggIDwAAAA==.Voltamatron:BAAANQAECgIIAgAAAA==.Vonbae:BAAANQABCgQIBgAAAA==.Vondread:BAAANQABCgIIAgAAAA==.Vorthall:BAAANQAECgMIBAAAAA==.',
Vr='Vraaxx:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Vrithea:BAAANQAECgUIBwAAAA==.',
Vy='Vyn:BAAANQADCgcICwAAAA==.Vyndroll:BAAANQADCgIIAgAAAA==.Vyrelion:BAAANQADCggIDQAAAA==.Vyri:BAAANQADCggIDgAAAA==.',
['Vë']='Vërastrasza:BAAANQADCgUIBQAAAA==.',
['Vó']='Vóidberg:BAAANQADCgcIDAAAAA==.',
['Vô']='Vôidweaver:BAAANQABCgIIAgAAAA==.',
Wa='Wangbusan:BAAANQAECgUIBwAAAA==.Warpedsoul:BAAANQABCgIIAgABNQAECgIIAgABAAAAAA==.Warpone:BAAANQADCgQIBAAAAA==.Warrtag:BAEANQAECgQIBQAAAA==.Warsella:BAAANQADCgUICQAAAA==.Warvar:BAAANQADCgcIEAAAAA==.Warziilla:BAAANQADCgYIBgAAAA==.Wazzard:BAAANQAECgEIAQAAAA==.',
We='Weaz:BAAANQAECgUIBwAAAA==.Weisong:BAAANQAECgUIBgAAAA==.',
Wh='Whitelechuga:BAAANQADCgYIDgAAAA==.Whorvold:BAAANQADCgcIDQAAAA==.Whulf:BAAANQADCggIDgAAAA==.',
Wi='Width:BAAANQADCgUIBQAAAA==.Wildcatt:BAAANQAECgEIAQAAAA==.Wilier:BAAANQADCggIDgAAAA==.Willemdafel:BAAANQADCgYIBgAAAA==.Willsmith:BAAANQAECgcIDQAAAA==.Winda:BAAANQADCgYICgAAAA==.',
Wo='Wolfiez:BAAANQADCgMIAwAAAA==.Wompster:BAAANQAECgQIBAAAAA==.Wompyp:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.',
Wr='Wraithtenai:BAAANQAECgIIAwAAAA==.',
Wu='Wuggadari:BAAANQADCgUICQAAAA==.Wullun:BAAANQAECgIIAgAAAA==.Wutupnaga:BAAANQADCgEIAQAAAA==.',
Wy='Wymond:BAAANQADCgIIAgAAAA==.',
['Wá']='Wárlock:BAAANQADCgMIAwAAAA==.',
Xa='Xaikar:BAAANQADCggIDgAAAA==.Xanadrill:BAAANQADCgYICgABNQADCgYICgABAAAAAA==.Xanatriius:BAAANQAECgMIBAAAAA==.Xandiros:BAAANQAECgIIAgAAAA==.Xaveris:BAAANQADCgQIBAAAAA==.Xaviethan:BAAANQAECgEIAQAAAA==.',
Xe='Xerces:BAAANQADCgEIAQAAAA==.Xerrus:BAAANQADCggIDgAAAA==.',
Xi='Xiang:BAAANQADCgYIBwAAAA==.Xianwae:BAAANQADCgUIBQAAAA==.',
Ya='Yazra:BAAANQAECgIIAwAAAA==.',
Ye='Yensolo:BAAANQADCggIDgAAAA==.Yetidk:BAAANQADCggIDQAAAA==.',
Yl='Ylia:BAAANQADCggIDwAAAA==.Ylvara:BAAANQABCgQIBQABNQAECgUIBwABAAAAAA==.',
Yo='Youbuyquez:BAAANQAECgEIAQAAAA==.',
Yv='Yvaelle:BAAANQAECgIIAgAAAA==.Yvaelyn:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.',
['Yô']='Yôkai:BAAANQADCgEIAQAAAA==.',
Za='Zacycrockett:BAAANQADCgEIAQAAAA==.Zalrot:BAAANQAECgIIAgAAAA==.Zandér:BAAANQADCgYICwAAAA==.Zanpa:BAAANQADCggIDAAAAA==.Zantriana:BAAANQADCggIDgAAAA==.Zappipappi:BAAANQADCgQIBAAAAA==.Zaraendice:BAAANQADCggICAAAAA==.Zarcane:BAAANQADCggIDgAAAA==.Zarics:BAAANQADCgUIBQAAAA==.',
Ze='Zeebrina:BAAANQADCgYICQAAAA==.Zel:BAAANQADCgIIAgAAAA==.Zellerra:BAAANQAECgIIAgAAAA==.Zeltar:BAAANQADCggIDAAAAA==.Zephrl:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Zesper:BAAANQAECgYICAAAAA==.Zetukur:BAAANQADCgYIBwAAAA==.',
Zu='Zugpo:BAAANQAECgQIBAABNQAECgUIBgABAAAAAA==.Zuliena:BAAANQADCgQIBAAAAA==.Zumela:BAAANQADCggIDgAAAA==.Zuphrel:BAAANQAECgIIAgAAAA==.Zuunau:BAAANQADCgYIBgAAAA==.',
Zw='Zwara:BAAANQADCgcICAAAAA==.',
Zy='Zylander:BAAANQAECgQIBQAAAA==.Zyrek:BAAANQAECgIIAgAAAA==.',
['Zá']='Zápdos:BAAANQADCggIDQAAAA==.',
['Zé']='Zéphyre:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
['Zì']='Zìlk:BAAANQADCggIDwAAAA==.',
['Zô']='Zôltan:BAAANQADCgYIDgAAAA==.',
['Âe']='Âerô:BAAANQAECgMIBAAAAA==.',
['Æm']='Æmpty:BAAANQABCgMIAwAAAA==.',
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
