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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm="Kil'jaeden",name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aagra:BAAANQAECgEIAQAAAA==.Aar:BAAANQADCgYIBgAAAA==.',
Ab='Abenthy:BAAANQADCggIDQAAAA==.Abita:BAAANQABCgIIAgAAAA==.Abrocadaver:BAAANQADCgQIBAAAAA==.Abruu:BAAANQADCggIDwABNQADCggIEQABAAAAAA==.',
Ac='Actualdarno:BAAANQADCgYIBgAAAA==.',
Ad='Adhria:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.Admirlackbar:BAAANQADCggICAAAAA==.Adrahm:BAAANQADCgcIDQAAAA==.',
Ae='Aetheryx:BAAANQADCgYIBgAAAA==.',
Af='Aftrlight:BAAANQAECgEIAQAAAA==.Aftrsurges:BAAANQABCgQIBgABNQAECgEIAQABAAAAAA==.',
Ag='Ag:BAAANQADCggIDgAAAA==.Against:BAAANQADCgcIDQAAAA==.Ageth:BAAANQADCgIIAgAAAA==.Aggrocentral:BAAANQADCgYICwAAAA==.Agnomaly:BAAANQADCgYICwAAAA==.',
Ai='Ainocee:BAAANQAECgUICwAAAA==.',
Ak='Akahando:BAAANQADCgUIBQAAAA==.Akantijin:BAAANQADCgcIDQAAAA==.Akhon:BAAANQADCggIDAAAAA==.',
Al='Alaethia:BAAANQADCgIIAwAAAA==.Alberricus:BAAANQAECgIIAgAAAA==.Alecthemage:BAAANQAECgEIAgAAAA==.Alethía:BAAANQADCgYICQAAAA==.Alex:BAAANQAECgQIBAAAAA==.Alexithymìa:BAAANQAECgcIDAAAAA==.Alham:BAAANQADCgYICwAAAA==.Aliénor:BAAANQADCgYICQAAAA==.Allann:BAAANQADCggICAAAAA==.Allenmdu:BAAANQADCggIDgAAAA==.Allicrtotems:BAEANQAECgIIAQAAAA==.Alphacue:BAAANQAECgUIBgAAAA==.Alphaskull:BAAANQADCgcIDQAAAA==.Altboy:BAAANQADCgcIDQAAAA==.Aluminum:BAAANQADCggIDgAAAA==.Alvaras:BAAANQADCgIIAgABNQADCggIEAABAAAAAA==.Alxonk:BAAANQAECgQIBQAAAA==.',
Am='Amaelia:BAAANQADCgIIAgAAAA==.Amperiel:BAAANQADCggIDgAAAA==.Amul:BAAANQADCgEIAQAAAA==.',
An='Andarise:BAAANQADCggIDgAAAA==.Andorihn:BAAANQAECgcIDQAAAA==.Andreah:BAAANQAECgQIBAAAAA==.Andross:BAAANQAECggICgAAAA==.Anehkara:BAAANQAECgQIBgAAAA==.Angrypincone:BAAANQAECgEIAQAAAA==.Anklebuster:BAAANQADCgYIBgAAAA==.Anndarnna:BAAANQADCgYIBgAAAA==.Ansagar:BAAANQADCgYICwAAAA==.',
Ao='Aonishiki:BAAANQADCgYIBgAAAA==.Aotahil:BAAANQADCgEIAQAAAA==.',
Ap='Apastron:BAAANQAECgMIAwAAAA==.Apexmachine:BAAANQAECgQIBgAAAA==.Apocalyticuh:BAAANQAECgMIAwAAAA==.Applemancy:BAAANQADCgYICwAAAA==.',
Ar='Aradryn:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.Arakani:BAAANQADCgMIAwAAAA==.Arcanefurry:BAAANQAECgEIAQAAAA==.Arcanemane:BAAANQAECgMIAwAAAA==.Archanos:BAAANQADCgYICgAAAA==.Archæmedes:BAAANQADCgYIBgAAAA==.Areiks:BAAANQADCggICwAAAA==.Arezzo:BAAANQADCgYIBgAAAA==.Aristae:BAAANQAECgQIBAAAAA==.Aritusk:BAAANQADCggIDgAAAA==.Armadar:BAAANQADCgYICgAAAA==.Arrakkiss:BAAANQAECgMIAwAAAA==.Artham:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.Artzam:BAAANQADCgUICQAAAA==.Artèmîs:BAAANQAECgUIBwAAAA==.Arês:BAAANQABCgMIAwABNQAECgUIBwABAAAAAA==.',
As='Ashna:BAAANQADCgIIAgAAAA==.Ashtal:BAAANQADCgYIBgAAAA==.Ashyna:BAAANQADCgYICwAAAA==.Askanswer:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Assc:BAAANQAECgIIAgAAAA==.Assd:BAAANQADCggICQAAAA==.Assmar:BAAANQADCgIIAgAAAA==.Asterus:BAAANQAECgMIAwAAAA==.Astole:BAAANQAECgEIAQAAAA==.Astralshards:BAAANQAECgUIBgAAAA==.',
At='Atchoöm:BAAANQAECgEIAQABNQAECgEIAgABAAAAAA==.Atheen:BAAANQADCgUIBQAAAA==.Athrad:BAAANQADCggIDgAAAA==.Atlantiss:BAAANQADCgYICwAAAA==.Attiliana:BAAANQADCgEIAQAAAA==.',
Au='Auntiemini:BAAANQADCgIIAgAAAA==.',
Av='Avinelle:BAAANQADCgUIBQAAAA==.',
Aw='Awenno:BAAANQADCggIDgAAAA==.',
Ax='Axsoul:BAAANQADCgIIAgAAAA==.Axyorix:BAAANQADCggIDgAAAA==.',
Ay='Ayimmadruid:BAAANQADCgEIAQAAAA==.',
Az='Azivalla:BAAANQAECgIIAgAAAA==.Azohkhan:BAAANQADCgEIAQAAAA==.Azurered:BAAANQABCgQIBAAAAA==.Azylblood:BAAANQAECgYIBwAAAA==.',
['Aö']='Aösoth:BAAANQADCggIEAABNQADCggIEQABAAAAAA==.',
Ba='Babayagazole:BAAANQAECgMIAwAAAA==.Bagpipe:BAAANQADCgUIBQABNQADCgYIBwABAAAAAA==.Bailrog:BAAANQADCgMIAwAAAA==.Bainbain:BAAANQADCgYICgAAAA==.Bald:BAAANQAECggIAQAAAA==.Baldonado:BAAANQADCgUICQAAAA==.Ballistic:BAAANQADCgcIDQAAAA==.Bamms:BAAANQAECgEIAQAAAA==.Bandaïd:BAAANQAECgEIAgAAAA==.Banryu:BAAANQADCgYICwAAAA==.Banshers:BAAANQAECgcIDQAAAA==.Barbie:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Bawlzy:BAAANQAECgQIBAAAAA==.',
Be='Bearbear:BAAANQADCgcICwAAAA==.Bedo:BAAANQAECgIIAgAAAA==.Beenbag:BAAANQADCgYIBwAAAA==.Beersbie:BAAANQADCgYIDAAAAA==.Bellatrex:BAAANQADCgMIAwAAAA==.Bellawraith:BAAANQADCgcICwAAAA==.Bellybuttom:BAAANQAECgUICQAAAA==.Bellybuttum:BAAANQAECgQIBAAAAA==.Benevolencel:BAAANQAECgUICwAAAA==.Benichi:BAAANQADCgcIEwAAAA==.Bennyboucher:BAAANQAECgEIAQAAAA==.Bequi:BAAANQAFFAIIAwAAAA==.Berko:BAAANQADCgIIAwAAAA==.Berserked:BAAANQAECgMIAwAAAA==.Bertoxulous:BAAANQAECgMIAwAAAA==.',
Bi='Bigblacku:BAAANQAECgQIBAABNQADCggIDgABAAAAAA==.Bigbullie:BAAANQADCgIIAgAAAA==.Bigoledingus:BAAANQADCggICAAAAA==.Bigpuli:BAAANQADCgQIBAAAAA==.Bigsplosions:BAAANQAECggIDAAAAA==.Bigweenuk:BAAANQABCgEIAQAAAA==.Bizarrogman:BAAANQAECgUIBgAAAA==.',
Bj='Bjorniron:BAAANQADCgMIAwAAAA==.',
Bk='Bkunstopable:BAAANQAECgIIAgAAAA==.',
Bl='Blashezi:BAAANQAECgQIBwAAAA==.Blazeing:BAAANQAECgEIAQAAAA==.Bleek:BAAANQADCgcIDQAAAA==.Blessìng:BAAANQADCgYIBgAAAA==.Blitztank:BAAANQADCgQIBAAAAA==.Blkbeerd:BAAANQAECgIIAgAAAA==.Blumary:BAAANQAECgQIBAAAAA==.',
Bo='Bobblegodx:BAAANQAECgcIDQAAAA==.Bobturd:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.Bogarn:BAAANQAECgcIDQAAAA==.Bohemeth:BAAANQADCgYIBgAAAA==.Bojangmatiki:BAAANQAECgIIAgAAAA==.Boldenone:BAAANQAECgQIBAAAAA==.Boltmobb:BAAANQAECgEIAQAAAA==.Bombido:BAAANQADCgYIBgAAAA==.Bonde:BAAANQAECgEIAQAAAA==.Bonguetongue:BAAANQADCggICQAAAA==.Bonobow:BAAANQADCgYICwAAAA==.Booggymaam:BAAANQADCgYICwAAAA==.Bookflipper:BAAANQADCgYIDAAAAA==.Borzanpal:BAAANQADCgYIBgAAAA==.',
Br='Brainwreck:BAAANQAECggICwAAAA==.Brassytotems:BAAANQADCggICAAAAA==.Brewsamdi:BAAANQAECgQIBAAAAA==.Brewtastic:BAAANQADCggICAAAAA==.Bro:BAAANQAECgcICwAAAA==.Brokzun:BAAANQAECgEIAQAAAA==.Bromass:BAAANQADCgQIBAAAAA==.Bronzefang:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Bruht:BAAANQADCgQIBAAAAA==.',
Bu='Bubblebie:BAAANQADCgYIBgAAAA==.Bullwinkel:BAAANQAECgMIBAAAAA==.Buttercakes:BAAANQADCggIDAAAAA==.Buttflapz:BAAANQABCgIIAgABNQAECgEIAQABAAAAAA==.Buttonz:BAAANQAECgEIAQAAAA==.',
['Bá']='Báleríon:BAAANQADCgUICQABNQADCgYIBgABAAAAAA==.',
['Bî']='Bîoshôcks:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Ca='Cabdomicus:BAAANQAECgYICQAAAA==.Cactdorn:BAAANQADCgYICwAAAA==.Calsu:BAAANQAECgEIAQAAAA==.Calum:BAAANQAECgIIAgAAAA==.Capriêstsun:BAAANQADCgYICAAAAA==.Cassandraa:BAAANQAECgEIAQAAAA==.Casuallyfoxy:BAAANQADCgYIDAAAAA==.',
Cb='Cba:BAAANQADCgMIAwAAAA==.',
Ce='Ceifadora:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Celestina:BAAANQAECgEIAQAAAA==.Cerberus:BAAANQAECgQIBwABNQAECgYICQABAAAAAA==.',
Ch='Chads:BAAANQAECgYIBgAAAA==.Chaosbeast:BAAANQADCgYIBgAAAA==.Chaosbrand:BAAANQAECgcICwABNQAFFAMIBAABAAAAAA==.Chaosovrflw:BAAANQADCgUIBQAAAA==.Chazban:BAAANQAECgMIAwAAAA==.Cherryx:BAAANQADCggIBgAAAA==.Chewbawk:BAAANQADCgYIBgAAAA==.Chichis:BAAANQAECgQIBAAAAA==.Chicknlil:BAAANQADCgYICwAAAA==.Chidiban:BAAANQADCggIBwAAAA==.Chihuolockz:BAAANQAECgUICQAAAA==.Chillguy:BAAANQAECgUICQAAAA==.Chilly:BAAANQAECgYICgAAAA==.Chimikui:BAAANQADCgUIBQAAAA==.Chittychitty:BAAANQADCgcIBwAAAA==.Chives:BAAANQAECgIIAgAAAA==.Chloe:BAAANQAECgIIAgAAAA==.Chonkymonky:BAAANQADCgcIDQAAAA==.Chopls:BAAANQABCgEIAQAAAA==.Chuggachops:BAAANQADCgYIBgAAAA==.Chupatits:BAAANQABCgIIAgAAAA==.Churchguy:BAAANQAECgQIBQAAAA==.Churchman:BAAANQAECggIDgAAAA==.Chàndrâ:BAAANQADCggIDgAAAA==.Chìefbeef:BAAANQAECgMIAwAAAA==.',
Ci='Cians:BAAANQAECgMIAwAAAA==.Cihuacoatl:BAAANQAECgEIAQAAAA==.',
Cj='Cjkzl:BAAANQADCgQIBAAAAA==.',
Cl='Cliinkz:BAAANQADCggICAAAAA==.Clorbid:BAAANQAECgEIAQAAAA==.',
Co='Coachradical:BAAANQAECgcIBwAAAA==.Codz:BAAANQAECgIIAwAAAA==.Cog:BAAANQADCgIIAgAAAA==.Coldbrew:BAAANQAECgEIAQAAAA==.Cometstrasza:BAAANQADCgQIBAABNQABCgQIBAABAAAAAA==.Coralie:BAAANQADCgcIDwAAAA==.Corellan:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.Corish:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Cosmicomics:BAAANQAECgUIBwAAAA==.Coverme:BAAANQADCgEIAQAAAA==.Cowmanjoe:BAAANQAECgEIAQAAAA==.Cozyfire:BAAANQAECgQIBwAAAA==.Cozywrath:BAAANQADCggIDwABNQAECgQIBwABAAAAAA==.',
Cp='Cptnpandemic:BAAANQAECgMIAwAAAA==.',
Cr='Crackedhead:BAAANQADCgcICQAAAA==.Craum:BAAANQADCgMIBAAAAA==.Crazed:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Creachy:BAAANQAFFAMIAwAAAA==.Creatos:BAAANQADCgMIBgABNQAECgIIBAABAAAAAA==.Cronchey:BAAANQADCgEIAQAAAA==.Crow:BAAANQAECgIIAgAAAA==.Crusherino:BAAANQADCggIEAAAAA==.Cryomental:BAAANQADCggICAAAAA==.Cryopally:BAAANQAECgEIAQAAAA==.Crôvàx:BAAANQADCgcIDQAAAA==.',
Ct='Ctun:BAAANQADCgQIBgAAAA==.',
Cu='Cuddlpuddl:BAAANQADCggIDgAAAA==.Cutiecutie:BAAANQADCgYIBgAAAA==.',
Cy='Cyclops:BAAANQADCgYICwAAAA==.',
['Cò']='Còlossus:BAAANQAECgEIAQAAAA==.',
Da='Daae:BAAANQAECgQIBQAAAA==.Dabnsmash:BAAANQAECgEIAQAAAA==.Dadaarionix:BAAANQADCggICwAAAA==.Daemage:BAAANQAECgUIBQAAAA==.Daemagor:BAAANQAECgQIBAAAAA==.Daemerok:BAAANQAECgMIAwAAAA==.Daledo:BAAANQADCgYICQAAAA==.Dalo:BAAANQAECgYICgAAAA==.Damnedsayer:BAAANQAECgEIAQAAAA==.Darimath:BAAANQADCgIIAgAAAA==.Darkam:BAAANQADCgYIBgAAAA==.Darzab:BAAANQAECgcICQAAAA==.Dassin:BAAANQADCgYIBgAAAA==.Dawndraper:BAAANQADCgMIAwAAAA==.Daxximus:BAAANQAECgEIAgAAAA==.Dazuggler:BAAANQAECgEIAQAAAA==.',
De='Deadlydough:BAAANQADCggICAAAAA==.Deathblóssóm:BAAANQADCggIDgAAAA==.Deathdoheal:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.Deathiras:BAAANQADCgYIBgAAAA==.Deathjaiden:BAAANQADCgYICwAAAA==.Decidence:BAAANQAECgYIBwAAAA==.Deejey:BAAANQAECgIIAgAAAA==.Delillidan:BAAANQAECgIIAgAAAA==.Demonbully:BAAANQAECgIIAgAAAA==.Denkou:BAAANQAECgQIBQAAAA==.Denteria:BAAANQAECgQIBAAAAA==.Deoxys:BAAANQADCgYIBgAAAA==.Derieri:BAAANQADCgMIAwAAAA==.Dersp:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Dersw:BAAANQAECggIDwAAAA==.Desaevio:BAAANQAECgIIAgAAAA==.Desecrator:BAAANQADCgMIAwAAAA==.Destwuction:BAAANQADCgYICwAAAA==.',
Dh='Dharken:BAAANQADCgUIBQAAAA==.Dhkhodie:BAAANQADCgYIBgAAAA==.Dhouse:BAAANQADCgEIAQAAAA==.',
Di='Diggi:BAAANQAECgEIAQAAAA==.Dingleshammy:BAAANQADCgQIBAAAAA==.Dinosaurman:BAAANQADCgEIAQAAAA==.Dippyswoop:BAAANQAECgMIAwAAAA==.Diralie:BAAANQADCgYIBwAAAA==.Dirtypew:BAAANQAECgIIAgAAAA==.Disastrous:BAAANQAECgYIBwAAAA==.Disloco:BAAANQAECgcIDAAAAA==.Dixinormus:BAAANQAECgQIBAAAAA==.Dizcuits:BAAANQAECgQIBAAAAA==.Dizztruction:BAAANQAECgMIAwAAAA==.',
Do='Doctonice:BAAANQAECgMIAwAAAA==.Dopamean:BAAANQADCgYICwAAAA==.Dordrian:BAAANQADCgYICAAAAA==.Dornadag:BAAANQADCgQIBAAAAA==.',
Dr='Draaz:BAAANQAECgMIAwAAAA==.Dracthong:BAAANQADCgYICgAAAA==.Draggindeez:BAAANQAECgMIAwAAAA==.Draginbrry:BAAANQADCgYICwAAAA==.Dragonexarch:BAAANQAECgcICwAAAA==.Draret:BAAANQAECgQIBAAAAA==.Draziq:BAAANQADCgIIAgAAAA==.Drdeathdude:BAAANQADCgcIDQAAAA==.Dreadkso:BAAANQADCgYIBgAAAA==.Dreamboy:BAAANQADCgYICwABNQAECgYICgABAAAAAA==.Drenim:BAAANQAECgUIBwAAAA==.Drethak:BAAANQADCgYIBgAAAA==.Drigiin:BAAANQAECgEIAQAAAA==.Drizzye:BAAANQADCgQIBAAAAA==.Drkilluquick:BAAANQADCgIIAgAAAA==.Drrockdapus:BAAANQAECgIIAgABNQAECgUIBwABAAAAAA==.Drrokzo:BAAANQADCgYIBwAAAA==.Druguser:BAAANQAECgEIAQAAAA==.Drunksob:BAAANQADCgYICwAAAA==.Dråk:BAAANQADCgUIBQABNQAECgQIBwABAAAAAA==.Dræmscape:BAAANQAECgEIAQAAAA==.Drìden:BAAANQADCgQIBQAAAA==.',
Du='Duk:BAAANQAECgEIAQAAAA==.Duncani:BAAANQADCggIDgAAAA==.',
Dv='Dvala:BAAANQADCgYIBgAAAA==.',
Dw='Dwarfenjoyer:BAAANQADCgYIBgAAAA==.Dwarfndecay:BAAANQAFFAMIBAAAAA==.Dwarfpunch:BAAANQADCgQIBAAAAA==.Dwilf:BAAANQADCggIEAAAAA==.',
Dy='Dyatso:BAAANQADCgQIBAAAAA==.Dynahuun:BAAANQADCggIDgAAAA==.Dysdain:BAAANQADCgcIDAAAAA==.Dyslite:BAAANQAECgEIAQAAAA==.',
['Dß']='Dß:BAAANQAECgcIDQAAAA==.',
['Dé']='Désco:BAAANQADCgcIDgAAAA==.Déspair:BAAANQADCgQIBAAAAA==.',
['Dë']='Dënt:BAAANQADCgcIDQAAAA==.',
['Dù']='Dùncan:BAAANQAECgUICgAAAA==.',
Ea='Eaglechïld:BAAANQADCgYICwAAAA==.',
Ed='Edamzz:BAAANQAECgIIAgAAAA==.',
Ei='Eiravael:BAAANQADCggIDgAAAA==.',
El='Eladar:BAAANQAECgMIAwAAAA==.Elfforhire:BAAANQADCggIDgAAAA==.Elfkenny:BAAANQADCggICAAAAA==.Elias:BAAANQAECgYICQAAAA==.Eliphas:BAAANQAECgEIAQAAAA==.Elithyra:BAAANQADCgUICgAAAA==.Elloment:BAAANQAECgEIAQAAAA==.Elmra:BAAANQADCggIDAAAAA==.Elsinora:BAAANQADCgUIBQAAAA==.Elyine:BAAANQAECgQIBQAAAA==.Elysus:BAAANQADCgYICwAAAA==.',
Em='Emelianenko:BAAANQADCgUIBgAAAA==.Emerc:BAAANQADCgEIAQAAAA==.Emphir:BAAANQADCgEIAQAAAA==.Empriza:BAAANQAECgIIAgAAAA==.',
En='Ene:BAAANQADCggIDgAAAA==.',
Er='Eratreya:BAAANQADCgcIDAAAAA==.Eredosia:BAAANQADCgQIBAAAAA==.Erektrigger:BAAANQADCgUICAABNQAECgMIAwABAAAAAA==.Erendi:BAAANQAECgIIAgAAAA==.Erissae:BAAANQADCgcIDAAAAA==.Eroztok:BAAANQADCggIDgAAAA==.',
Es='Eskano:BAAANQADCgUICgAAAA==.',
Eu='Eurydicee:BAAANQADCgYIBgAAAA==.',
Ev='Everretta:BAAANQADCgYIBgAAAA==.Evilyeti:BAAANQADCggIDgAAAA==.Evoares:BAAANQAECgUIBwAAAA==.Evokussy:BAAANQAECggICwAAAA==.',
Ex='Extasea:BAAANQAECgIIAgAAAA==.',
Ey='Eygon:BAAANQAECgIIAgAAAA==.',
Ez='Ezgrip:BAAANQAECgEIAQAAAA==.',
Fa='Fabgee:BAAANQABCgMIAwABNQAFFAIIAgABAAAAAA==.Faedra:BAAANQADCgIIAgAAAA==.Falalala:BAAANQADCgYICQAAAA==.Farmertran:BAAANQAECgIIAgAAAA==.Fatq:BAAANQAECgIIAgAAAA==.',
Fb='Fbt:BAAANQAECgQIBwAAAA==.',
Fc='Fc:BAAANQADCgcIDQAAAA==.',
Fe='Felforged:BAAANQADCgcIBwABNQAECgYICAABAAAAAA==.Felixw:BAAANQAECgEIAQAAAA==.Fellien:BAAANQAECgQIBQABNQAECgcICwABAAAAAA==.Felljustice:BAAANQAECgUIBgAAAA==.Fellmixx:BAAANQAECgcICwAAAA==.Fellshadow:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Felnath:BAAANQAECgUIBgAAAA==.Felronn:BAAANQADCggIEAAAAA==.Femboyloover:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Fenrir:BAAANQABCgQIBAAAAA==.Feraldruid:BAAANQADCgcIBwAAAA==.Ferngutter:BAAANQADCgIIAgAAAA==.',
Fi='Fieryblack:BAAANQADCggIDwAAAA==.Fierykatt:BAAANQADCgYIDAAAAA==.Fierymonk:BAAANQADCgcIDgAAAA==.Filthydruid:BAAANQAECgMIAwAAAA==.Firekushin:BAAANQAECggIAgAAAA==.Fitnessmodel:BAAANQAECgIIAgAAAA==.Fixxer:BAAANQADCgYIBgAAAA==.',
Fl='Flashmagic:BAAANQAFFAEIAQAAAA==.Flashmajik:BAAANQAECgQIBAAAAA==.Flasken:BAAANQADCggICAAAAA==.Flaymignon:BAAANQADCgYIBgAAAA==.Flem:BAAANQADCgcIDQAAAA==.Fleshthief:BAAANQADCgYICwAAAA==.Flobby:BAAANQADCggICgAAAA==.Floemental:BAAANQADCggICwAAAA==.Flosap:BAAANQADCgQIBAAAAA==.Fluffywub:BAAANQADCgcICgAAAA==.',
Fo='Fookshunter:BAAANQADCgYIBgAAAA==.Foonchi:BAAANQADCggIDQAAAA==.Forcefultomb:BAAANQAECgIIAwABNQAECgMIAwABAAAAAA==.Foringo:BAAANQADCgYIBwAAAA==.Fotoaparate:BAAANQADCgIIAgAAAA==.Foxus:BAAANQADCgIIAgAAAA==.',
Fr='Fragility:BAAANQAECgMIAwABNQAECggIDwABAAAAAA==.Franciscus:BAAANQADCgYICQAAAA==.Frappefort:BAAANQADCgUIBQAAAA==.Frobulator:BAAANQAECgQIBQABNQAECgUIBQABAAAAAA==.Frop:BAAANQAECgIIAgAAAA==.Frostipookie:BAAANQAFFAIIAgAAAA==.Frostyfriend:BAAANQADCgYIBgAAAA==.Frozlotus:BAAANQADCgcICwAAAA==.Frubalunta:BAAANQADCgYIBwAAAA==.',
Fu='Fuldall:BAAANQADCgQIBQABNQADCggIEQABAAAAAA==.Funckle:BAAANQADCgcIBwAAAA==.Furyious:BAAANQAECgEIAQAAAA==.Fuzywuzycow:BAAANQAECgQIBQAAAA==.Fuzzyheels:BAAANQADCgMIAwABNQAECgcIDAABAAAAAA==.',
['Fá']='Fácemé:BAAANQADCgYIDAAAAA==.',
Ga='Galahåd:BAAANQAECgQIBgABNQADCgYICgABAAAAAA==.Galakrond:BAAANQADCgcIBwAAAA==.Galíath:BAAANQAECgQIBAAAAA==.Ganeeshka:BAAANQAECgQIBQAAAA==.Ganenn:BAAANQADCggIEAAAAA==.Gaoul:BAAANQAECgQIBAAAAA==.Gardiff:BAAANQAECggICAAAAA==.Garfumaw:BAAANQADCgQIBAAAAA==.',
Ge='Genau:BAAANQAECgQIBgABNQAECgYICQABAAAAAA==.Genzin:BAAANQADCgQIBgAAAA==.Gerftraz:BAAANQAECgEIAQAAAA==.Gerrath:BAAANQADCgcIDQAAAA==.',
Gh='Ghostrobot:BAAANQADCgMIAwAAAA==.Ghóuls:BAAANQAECgQIBwAAAA==.',
Gi='Gibari:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Gigaook:BAAANQAECgEIAQAAAA==.Gillagos:BAAANQADCggICwAAAA==.Gixa:BAAANQADCgYIBgAAAA==.',
Gl='Glaivedriel:BAAANQADCgUICAAAAA==.Glashkaa:BAAANQADCgQIBAAAAA==.Glasinda:BAAANQAECgUIBQAAAA==.Glitchflight:BAAANQADCggIDgABNQAECgcIDAABAAAAAA==.Glizzinate:BAAANQADCgUICgAAAA==.Glizzurd:BAAANQADCgEIAQAAAA==.Glorymaster:BAAANQADCgYIDAAAAA==.Glupglup:BAAANQADCgUIBgAAAA==.Glör:BAAANQAECgQICwAAAA==.',
Go='Goraq:BAAANQAECgIIAgAAAA==.Gorehowl:BAAANQADCgEIAQAAAA==.Gosu:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Gotlust:BAAANQAECgQIBAAAAA==.',
Gr='Graider:BAAANQAECgYICgAAAA==.Gramroll:BAAANQAECgEIAQAAAA==.Graytakeo:BAAANQADCggIDgAAAA==.Greeksauce:BAAANQAECgMIBQAAAA==.Greengrapey:BAAANQADCgYICwAAAA==.Grendahlia:BAAANQAECgQIBAABNQADCgUIBQABAAAAAA==.Grenthoryl:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Grimforge:BAAANQADCgQIBAAAAA==.Grimmcow:BAAANQADCgIIAgAAAA==.Grimothy:BAAANQADCgYICwAAAA==.Grockedout:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Grogthefist:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Grricky:BAAANQAECgcICwAAAA==.Gruggi:BAAANQADCgcIDQAAAA==.Grugthesquat:BAAANQADCgEIAQAAAA==.Grundie:BAAANQADCgMIAwAAAA==.Grymex:BAAANQADCgcIBwAAAA==.Grómm:BAAANQADCgcIDQAAAA==.',
Gu='Guerreradogg:BAAANQADCgcICgAAAA==.Gugg:BAAANQAECgQIBAABNQAECgYICgABAAAAAA==.Guissepi:BAAANQADCggIDgAAAA==.Gunchi:BAAANQADCgEIAQABNQAECgcICQABAAAAAA==.Gundyy:BAAANQAECgcICQAAAA==.Gusbuspriest:BAAANQAECgEIAQAAAA==.Gustafer:BAAANQADCggICwAAAA==.',
Gw='Gwathrenaur:BAAANQADCgcIDAAAAA==.',
Gy='Gymmyshot:BAAANQAECgQIBwAAAA==.',
['Gé']='Géodesic:BAAANQAECgMIAwAAAA==.',
Ha='Haaw:BAAANQAECgIIAgAAAA==.Hadise:BAAANQAFFAEIAQAAAA==.Hailine:BAAANQADCgcIBwABNQADCggIEAABAAAAAA==.Halacs:BAAANQADCgYIBgAAAA==.Hammerstorm:BAAANQAECggIDgAAAA==.Hamwater:BAAANQADCgYIBgAAAA==.Hanthe:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Happychaos:BAAANQAECgQICAAAAA==.Haraskore:BAAANQAECgMIAwAAAA==.Harrydingle:BAAANQADCgEIAQAAAA==.Hathor:BAAANQABCgMIAwABNQAECgIIAgABAAAAAA==.Haurez:BAAANQADCgEIAQAAAA==.Hawthira:BAAANQADCgQIBAAAAA==.Haytham:BAAANQAECgcIDQAAAA==.',
He='Healarybuff:BAAANQADCgYICwAAAA==.Heinric:BAAANQAECgMIAwABNQAECggICQABAAAAAA==.Hellion:BAAANQADCgcIDQAAAA==.Hellongirth:BAAANQADCggIDAAAAA==.Hellscreåm:BAAANQAECgQIBwAAAA==.Hemodynamics:BAAANQADCgMIAwAAAA==.Henaku:BAAANQADCgEIAQAAAA==.Hetril:BAAANQADCggICAAAAA==.Hexadin:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Hexdk:BAAANQAECgEIAQAAAA==.',
Hi='Hiddensheep:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Hiimmas:BAAANQADCgYIBgABNQAFFAMIAwABAAAAAA==.Hildii:BAAANQADCggIDgAAAA==.Hildin:BAAANQADCggICAAAAA==.Himikoto:BAAANQADCgcIBwAAAA==.Hisheaven:BAAANQADCgYIBgAAAA==.',
Hl='Hlywilamsfan:BAAANQAECgYICgAAAA==.',
Ho='Hoeelycow:BAAANQAECgMIAwAAAA==.Hokulani:BAAANQADCgcICgAAAA==.Hollend:BAAANQAFFAEIAQAAAA==.Holycritty:BAAANQADCggICAAAAA==.Holyhll:BAAANQAECgEIAQAAAA==.Holyovrflw:BAAANQAECgEIAQAAAA==.Homodatinapp:BAAANQAECgQIBQAAAA==.Homuncul:BAAANQADCgUIBwAAAA==.Honju:BAAANQAECgIIAgAAAA==.Hooey:BAAANQAECgIIAgAAAA==.Hordemaster:BAAANQAECgYICgAAAA==.Hornchata:BAAANQADCgYICwAAAA==.Horshack:BAAANQAECgEIAQAAAA==.Hosannahh:BAAANQAECgYICgAAAA==.Hotlatte:BAAANQAECgMIAwAAAA==.Howdoihealz:BAAANQADCgcIBwAAAA==.',
Hr='Hrongrega:BAAANQAECgIIAgAAAA==.Hruni:BAAANQADCgYICgAAAA==.',
Hu='Hukinata:BAAANQADCggIDgAAAA==.Hunkytwunky:BAAANQADCgYIBgAAAA==.Hurron:BAAANQADCggICAAAAA==.',
Hy='Hydrocodiene:BAAANQADCgYICQAAAA==.Hydrolix:BAAANQAECgIIAgAAAA==.',
['Hè']='Hèkå:BAAANQAECgIIAgAAAA==.',
Ia='Iamluck:BAAANQAECgYICwAAAA==.Iamtooyellow:BAAANQAECgMIBAAAAA==.',
Ib='Ibunz:BAAANQAECgEIAQAAAA==.',
Ic='Iceborn:BAAANQAECgMIAwAAAA==.Icedveins:BAAANQAECgQIBAAAAA==.Icemango:BAAANQADCggICAAAAA==.',
Id='Idiotfel:BAAANQAECggICwAAAA==.',
Ig='Ignexious:BAAANQADCgMIAwAAAA==.Ignïs:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Igotadklol:BAAANQAECgQIBAAAAA==.',
Ih='Ihr:BAAANQADCgYIBwAAAA==.',
Ik='Ikha:BAAANQAECgMIAwAAAA==.',
Il='Illremedy:BAAANQADCggIDQAAAA==.Illuminnae:BAAANQAECgQIBQAAAA==.Illuvata:BAAANQAECgEIAQAAAA==.',
Im='Imabadhunter:BAAANQADCggIDwAAAA==.Imoanrence:BAAANQAECgQIBwAAAA==.Implode:BAAANQAECgUICQAAAA==.Impudent:BAAANQAFFAEIAQAAAA==.Imsheepdup:BAAANQADCgcIDQAAAA==.',
In='Insane:BAAANQAECgUICgAAAA==.Insidejob:BAAANQADCgQIBQAAAA==.Int:BAAANQAECgcICQABNQADCggIEAABAAAAAA==.Inxs:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.',
Ip='Ipwntheorcs:BAAANQADCggIDQAAAA==.',
Ir='Iralos:BAAANQADCggIDgAAAA==.Ironclâd:BAAANQAECgQICAAAAA==.Ironheårt:BAAANQAECggIAgAAAA==.Ironsmash:BAAANQADCgYIBgAAAA==.Irrev:BAAANQAECgQIBQAAAA==.',
Is='Isabouttodie:BAAANQADCgYICgAAAA==.Iseult:BAAANQAECgEIAQAAAA==.Issalar:BAAANQADCgcICQAAAA==.',
It='Itaroo:BAAANQAECgMIAwAAAA==.Itsdahulk:BAAANQAECggICQAAAA==.',
Iy='Iyasu:BAAANQADCggIDgAAAA==.',
Iz='Izumire:BAAANQADCggIDgAAAA==.',
Ja='Jabzarnluz:BAAANQADCgcIBQAAAA==.Jadethunder:BAAANQAECgEIAQAAAA==.Jagd:BAAANQADCgIIAgAAAA==.Jaggu:BAAANQADCgUIBQAAAA==.Jalanni:BAAANQADCgQIBAAAAA==.Januak:BAAANQADCggICAABNQAECgUICAABAAAAAA==.Janya:BAAANQADCgcICwAAAA==.Jarilla:BAAANQADCgcIBwAAAA==.Jasè:BAAANQABCgMIBAAAAA==.Jayex:BAAANQADCgYIBgAAAA==.',
Je='Jelloly:BAAANQADCgYICgAAAA==.Jencky:BAAANQADCgIIAgAAAA==.Jesterjuice:BAAANQADCgYIBgAAAA==.',
Ji='Jigbizzle:BAAANQAECgMIAwAAAA==.Jindank:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Jinsinn:BAAANQAECgYICwAAAA==.',
Jo='Jobbings:BAAANQADCgUIBwAAAA==.Joefutofu:BAAANQADCgUICgAAAA==.Jondoscaria:BAAANQADCggIDgAAAA==.',
Ju='Juanita:BAAANQADCgQIBAAAAA==.Juicyberries:BAAANQADCgQICAABNQADCgUIBQABAAAAAA==.Juliagoolea:BAAANQAECgQIBAAAAA==.Jurrasicbark:BAAANQAECgQIBgAAAA==.Justicia:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Juyo:BAAANQAECgYIBgAAAA==.',
['Jø']='Jøhnny:BAAANQADCgcIDAAAAA==.',
Ka='Kaeslappy:BAAANQADCgcIDQAAAA==.Kaladhin:BAAANQAECgIIAgAAAA==.Kalomee:BAAANQAECgEIAQAAAA==.Kamaelin:BAAANQAECgYICwAAAA==.Kandekid:BAAANQABCgEIAQAAAA==.Karatiekid:BAAANQADCggICAAAAA==.Karaxes:BAAANQADCgQIBAAAAA==.Karnality:BAAANQAECgEIAQAAAA==.Kasiee:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.Katemeshi:BAAANQADCgUIBQAAAA==.Kaydrie:BAAANQADCggIFgAAAA==.Kayyce:BAAANQAECgQIBAAAAA==.Kazaku:BAAANQADCggIEAAAAA==.Kazii:BAAANQAECgEIAQAAAA==.Kaíju:BAAANQADCgUIBQAAAA==.',
Ke='Keekkz:BAAANQAECgMIBQAAAA==.Keekzdh:BAAANQADCggICAAAAA==.Keikoa:BAAANQAECgQIBQAAAA==.Keldan:BAAANQAECgYIBwAAAA==.Kelinas:BAAANQADCgcIBwAAAA==.Kelm:BAAANQAECgEIAQAAAA==.Kelsii:BAAANQADCgMIAwAAAA==.Kentetsu:BAAANQADCggIDgAAAA==.Ketang:BAAANQADCgcIBwAAAA==.',
Kg='Kg:BAAANQADCgUICgAAAA==.',
Kh='Khayden:BAAANQAECgEIAQAAAA==.Khiseer:BAAANQAECgIIAgAAAA==.Khodiie:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Khybrew:BAAANQADCggICAAAAA==.',
Ki='Kihon:BAAANQADCggICAABNQADCggIDgABAAAAAA==.Kiralni:BAEANQADCggIDgAAAA==.Kitanno:BAAANQADCgUIBQAAAA==.Kitano:BAAANQADCgYIBgAAAA==.Kitanoh:BAAANQADCgMIAwAAAA==.Kitanoo:BAAANQADCgcICQAAAA==.Kitsuna:BAAANQAECgEIAQAAAA==.Kitsunaei:BAAANQABCgIIAgAAAA==.Kizzer:BAAANQAECgMIAwAAAA==.',
Kl='Kluckers:BAAANQADCggIDQAAAA==.',
Kn='Kneadious:BAAANQAECgYICgAAAA==.Knuckless:BAAANQADCgQIAwAAAA==.',
Ko='Kombi:BAAANQADCgYIDAABNQAECgYICgABAAAAAA==.Konata:BAAANQADCggIDgAAAA==.Kotoong:BAAANQAECgUIBwAAAA==.',
Kr='Kromiko:BAAANQADCgUIBQAAAA==.Krugthesquat:BAAANQADCgUIBQAAAA==.Kryptin:BAAANQADCgMIBQAAAA==.',
Ku='Kucerakov:BAAANQADCgcIDQAAAA==.Kuixotic:BAAANQADCggIDAAAAA==.Kullmage:BAAANQADCgMIAwAAAA==.Kurgerbingg:BAAANQADCgcICQAAAA==.Kuthara:BAAANQAECgQIBAAAAA==.Kuuter:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Kw='Kwatar:BAAANQADCggICAAAAA==.Kwemm:BAAANQADCggIDgAAAA==.Kweywey:BAAANQAECgQIBAAAAA==.',
['Kå']='Kålina:BAAANQABCgIIAgAAAA==.',
['Kì']='Kìed:BAAANQAECgEIAQAAAA==.Kìzaru:BAAANQADCgYIBgAAAA==.',
La='Labarbie:BAAANQABCgIIBAAAAA==.Lagaston:BAAANQAECgQIBQAAAA==.Lavvi:BAAANQADCgYIBwAAAA==.Layonbubble:BAAANQADCgMIAwAAAA==.',
Ld='Ldevon:BAAANQADCgQIBAAAAA==.',
Le='Leandara:BAAANQADCgYICwAAAA==.Lebosh:BAAANQADCgYIBgAAAA==.Leböwski:BAAANQAECgQICAAAAA==.Leftyh:BAAANQAECgIIAgAAAA==.Leftyw:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Legionofzole:BAAANQAECgMIAwABNQAECgMIAwABAAAAAA==.Legodruid:BAAANQAECgEIAQAAAA==.Legomonk:BAAANQADCggICAABNQAECgEIAQABAAAAAA==.',
Li='Liadryn:BAAANQAECgcIBwAAAA==.Lichkink:BAAANQAECgEIAQAAAA==.Lidage:BAAANQAECgcICgAAAA==.Lifeofpie:BAAANQABCgEIAQABNQAECgYIBwABAAAAAA==.Lightninjeff:BAAANQADCgUIBwAAAA==.Lightsworn:BAAANQADCgQIBgAAAA==.Lilithieda:BAAANQAECgIIAgAAAA==.Lios:BAAANQAECgEIAQAAAA==.Lipsync:BAAANQADCgUIBQAAAA==.Lisem:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Liviarra:BAAANQAECgIIAgAAAA==.',
Ll='Llamasham:BAAANQAECgMIAwAAAA==.Llasso:BAAANQADCggIDgAAAA==.',
Lo='Loakumoji:BAAANQADCgMIAwAAAA==.Loasparce:BAAANQADCgEIAQAAAA==.Loboasarus:BAAANQAECgMIAwAAAA==.Lockeecharms:BAAANQADCggIDgAAAA==.Loociver:BAAANQAECgYICQAAAA==.Lookey:BAAANQADCgcIDAAAAA==.Looterk:BAAANQAECgEIAQAAAA==.Loringstar:BAAANQADCgYIDAAAAA==.Loudfist:BAAANQADCggIDgAAAA==.',
Lt='Ltkerrigan:BAAANQAECgEIAQAAAA==.',
Lu='Lucienkioshi:BAAANQADCgQIBAAAAA==.Luckster:BAAANQADCgYICwAAAA==.Luminious:BAAANQAECgEIAQAAAA==.Lurknasty:BAAANQADCgYIBgAAAA==.',
Ly='Lyria:BAAANQAECgMIAwAAAA==.Lyssinda:BAAANQAECgQIBAAAAA==.',
['Lí']='Líte:BAAANQAECgcIDQAAAA==.',
['Lù']='Lùcý:BAAANQADCgQIBAAAAA==.',
Ma='Maavir:BAAANQAECgQIBQAAAA==.Machinadewar:BAAANQAECgIIAgAAAA==.Madeadk:BAAANQAECgYICgAAAA==.Madkow:BAAANQABCgEIAQAAAA==.Madwardog:BAAANQADCgIIAgAAAA==.Maerune:BAAANQADCgcIBwAAAA==.Mageiest:BAAANQAECgEIAQAAAA==.Magicpie:BAAANQADCggICgAAAA==.Magsham:BAAANQAECgEIAQAAAA==.Mahler:BAAANQAECgMIBAAAAQ==.Mahnsa:BAAANQADCggIDwAAAA==.Mailovissuga:BAAANQADCgUIBQAAAA==.Majpaynesh:BAAANQADCgYIBgAAAA==.Malphael:BAAANQAECgEIAQAAAA==.Manabending:BAAANQAECgMIAwAAAA==.Manayu:BAAANQADCgQIBAAAAA==.Marakurta:BAAANQADCggIEAAAAA==.Marcaris:BAAANQAECgMIAwAAAA==.Mariara:BAAANQADCgUIBQAAAA==.Marrcii:BAAANQAECgQIBAAAAA==.Marsaran:BAAANQAECgQIBQAAAA==.Mashaku:BAAANQADCgMIAwAAAA==.Mashedar:BAAANQAECgIIAgAAAA==.Masmune:BAAANQADCgQIBAAAAA==.Mathematical:BAAANQAECgEIAQAAAA==.',
Me='Meany:BAAANQADCggIDwAAAA==.Meatgripper:BAAANQAFFAEIAQABNQAFFAIIAgABAAAAAA==.Meddit:BAAANQADCgYIBgAAAA==.Mehulk:BAAANQAECgMIAwAAAA==.Melchioor:BAAANQADCggICAABNQADCggICAABAAAAAA==.Membrane:BAAANQADCgIIAgAAAA==.Menethil:BAAANQABCgQIBAAAAA==.Mercurios:BAAANQADCgUICQAAAA==.Mesò:BAAANQADCggIDgABNQAECgEIAQABAAAAAA==.Metsubo:BAAANQAECgUICAAAAA==.',
Mi='Michaelgpt:BAAANQAFFAIIAgAAAA==.Migss:BAAANQAECgMIAwAAAA==.Mikkiel:BAAANQADCgYIBwAAAA==.Milkshakes:BAAANQADCgUIBQAAAA==.Minishough:BAAANQADCgYIBgAAAA==.Mistweave:BAAANQAECggIDwAAAA==.Mithm:BAAANQADCggIDgAAAA==.',
Mn='Mnshamalan:BAEANQAECgEIAQAAAA==.',
Mo='Mondaymornin:BAAANQADCgcIDQAAAA==.Monächus:BAAANQAECgUICAAAAA==.Moontoast:BAAANQADCgcIBwAAAA==.Mordryd:BAAANQADCgYICgAAAA==.Morgawyn:BAAANQADCgcIDQAAAA==.Mortarius:BAAANQADCgcIDAAAAA==.Morthrax:BAAANQADCgIIAgAAAA==.Mosrage:BAAANQADCgEIAQABNQAECgEIAgABAAAAAA==.',
Mt='Mtnbrew:BAAANQAECgYIBwAAAA==.',
Mu='Muffinelf:BAAANQAECgMIBgAAAA==.Muggul:BAAANQADCggICgAAAA==.Muktukk:BAAANQADCgYIBgAAAA==.Muldan:BAAANQAECgIIAgAAAA==.Mun:BAAANQADCggIDgAAAA==.Murgl:BAAANQAECgQIBAAAAA==.Muushubeef:BAAANQADCgYIBwAAAA==.',
My='Mydotisbrown:BAAANQADCggIDgAAAA==.Myrothanor:BAAANQAECgIIAgAAAA==.Mythell:BAAANQAECgMIAwAAAA==.Mythictotem:BAAANQADCgYIDAAAAA==.Mythliatrix:BAAANQADCgYIBgAAAA==.',
['Mó']='Mórinth:BAAANQAECgQIBAAAAA==.',
['Mö']='Mönolith:BAAANQADCggIDwABNQADCggIEQABAAAAAA==.',
Na='Nachyoo:BAAANQADCgQIBAAAAA==.Nagafen:BAAANQADCggICwAAAA==.Nahalie:BAAANQAECgIIAgAAAA==.Naloxonne:BAAANQAECgEIAQAAAA==.Naomirence:BAAANQADCgYIBgAAAA==.Narcians:BAAANQADCgYIBgAAAA==.Nayeon:BAAANQAECgcIDQAAAA==.Naíx:BAAANQAECgQIBgAAAA==.',
Ne='Neat:BAAANQADCggIDgAAAA==.Nedious:BAAANQADCgQIBAAAAA==.Nekrovoid:BAAANQAECgUIBgAAAA==.Neoblaze:BAAANQADCgcIDQAAAA==.Neozug:BAAANQAECgYICQAAAA==.Nephyxo:BAAANQAECgcIDQAAAA==.Nerdlet:BAAANQADCgMIAwAAAA==.Ness:BAAANQADCggICwAAAA==.Neverthere:BAAANQADCgcIDAAAAA==.Nevoi:BAAANQABCgQIBAAAAA==.Nevonas:BAAANQAECgIIAgAAAA==.Newtybootie:BAAANQADCgUIBQAAAA==.Nexro:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ni='Nibroc:BAAANQADCgUIBgAAAA==.Nielsen:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.',
No='Nohk:BAAANQAECgIIAgAAAA==.Nolah:BAAANQAECgQIBgAAAA==.Nontal:BAAANQAECgMIAwAAAA==.Noodlle:BAAANQADCgcIBwAAAA==.Normanfisty:BAAANQAECgIIAgAAAA==.Norskito:BAAANQAECgYICgAAAA==.Northstarz:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Northzpal:BAAANQAECgQIBAAAAA==.Notsmaug:BAAANQAECgMIAwAAAA==.',
Nu='Nukunuku:BAAANQADCgYICgAAAA==.Numbnuttz:BAAANQAECgEIAQAAAA==.',
Ny='Nyall:BAAANQAECgIIAgAAAA==.Nymaris:BAAANQADCgYIBgAAAA==.',
Ob='Obliti:BAAANQADCggIDgAAAA==.',
Od='Odipal:BAAANQADCggIDgAAAA==.',
Oh='Ohnoo:BAAANQADCggIDgAAAA==.Ohplzgodno:BAAANQAECgcIDQAAAA==.',
Oi='Oidhe:BAAANQAECgIIAgAAAA==.',
Ok='Oktaï:BAAANQADCggICQAAAA==.',
Ol='Olgah:BAAANQADCgYICgAAAA==.',
Om='Omnislash:BAAANQAECgQIBAAAAA==.',
On='Onyxskies:BAAANQADCgYICwAAAA==.Onz:BAAANQADCgEIAQAAAA==.',
Oo='Oopsydaisy:BAAANQADCgMIBAAAAA==.',
Op='Opqt:BAAANQAECgIIAgAAAA==.',
Or='Oransrogue:BAAANQADCgYICgAAAA==.Orbmalian:BAAANQADCgMIAwAAAA==.Orcbum:BAAANQAECgcIDAAAAA==.Orddorfal:BAAANQAECggIDQAAAA==.Orthodontics:BAAANQAECggICAAAAA==.',
Ou='Outspaced:BAAANQAFFAIIAgAAAA==.Outsur:BAAANQAFFAIIAgAAAA==.Ouuch:BAAANQADCgQIBAAAAA==.',
Ox='Oxytøcin:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Pa='Padde:BAAANQADCgYIBgAAAA==.Palapex:BAAANQAECgQIBQAAAA==.Palliboi:BAAANQADCgIIAgAAAA==.Palucci:BAAANQAFFAEIAQAAAA==.Palwørld:BAAANQADCgMIBQAAAA==.Pandashock:BAAANQADCgQIBgABNQAECgQICAABAAAAAA==.Pandathug:BAAANQAECgQICAAAAA==.Panyot:BAAANQAECgEIAQAAAA==.Pastanoodle:BAAANQAFFAEIAQAAAA==.Patragon:BAAANQAECgEIAQAAAA==.Patricia:BAAANQADCggIEAABNQADCggIEQABAAAAAA==.Paulios:BAAANQAECgMIAwAAAA==.',
Pe='Peanutww:BAAANQAFFAEIAQAAAA==.Peek:BAAANQAECgMIAwAAAA==.Peredh:BAAANQAECgQIBQAAAA==.Permafrosti:BAAANQAECgQIBAAAAA==.Petêy:BAAANQAECgMIAwAAAA==.Peék:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.',
Ph='Phathoumn:BAAANQADCgYICwAAAA==.Phoxxy:BAAANQAECgEIAQAAAA==.',
Pi='Picayune:BAAANQADCgUIDAAAAA==.Pichihime:BAAANQADCgYICwAAAA==.Pickleprime:BAAANQAECgEIAQAAAA==.Pilk:BAAANQAECgEIAQAAAA==.Pilkbender:BAAANQAECgIIAgAAAA==.Pineaplxpres:BAAANQADCgYICwAAAA==.Pinez:BAAANQADCgEIAQAAAA==.Pinkburrito:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Pinkkivky:BAAANQADCgUICQAAAA==.Pipadin:BAAANQAECgQIBAAAAA==.Pirata:BAAANQAECgMIAwAAAA==.Pizzadip:BAAANQAECgIIAgAAAA==.',
Pj='Pj:BAAANQAECgEIAQAAAA==.',
Pk='Pkat:BAAANQAECgIIAgAAAA==.',
Pl='Plexxi:BAAANQAECgcIDQAAAA==.',
Po='Pocahantus:BAAANQADCggICwAAAA==.Poent:BAAANQADCgEIAQAAAA==.Poisonite:BAAANQADCgIIAgAAAA==.Pokedabear:BAAANQADCgYICwAAAA==.Polarez:BAAANQADCgcIAgAAAA==.Polomer:BAAANQAECgQIBQAAAA==.Pompeii:BAAANQAECgYIBwABNQAECgcIDwABAAAAAA==.Pondoh:BAAANQAECgMIAwAAAA==.Pondow:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Pongy:BAAANQADCgYIBwAAAA==.Pongyer:BAAANQADCggIDwAAAA==.Pooss:BAAANQAFFAMIBAAAAA==.Poptart:BAAANQAECgEIAgAAAA==.Postureczech:BAAANQADCgEIAQAAAA==.',
Pp='Pphardcore:BAAANQAECgQIBAAAAA==.Ppots:BAAANQADCggICwAAAA==.',
Pr='Premiumtax:BAAANQAECgQIBAAAAA==.Preparator:BAAANQAECgQIBgAAAA==.Preparetocry:BAAANQADCgYICgAAAA==.Pretty:BAAANQAECgMIBQAAAA==.Priscìlla:BAAANQAECgMIAwAAAA==.Protectyapet:BAAANQADCgYICgAAAA==.',
Ps='Pshaman:BAAANQAECgMIAwAAAA==.Psyonna:BAAANQADCgYIBwAAAA==.',
Pu='Pulveryze:BAAANQADCgEIAQAAAA==.Punchdandan:BAAANQADCgYIBgAAAA==.Punchmonk:BAAANQADCggIDgAAAA==.Purplehayes:BAAANQABCgIIAgAAAA==.Purra:BAAANQADCgcIBwAAAA==.',
Qo='Qordis:BAAANQADCgcICwAAAA==.',
Qu='Quallona:BAAANQADCgcIDQAAAA==.Quaruk:BAAANQABCgIIAgAAAA==.Quavo:BAAANQADCgUICQAAAA==.Quillix:BAAANQADCgUIBQAAAA==.',
Ra='Raamkar:BAAANQADCgYICgABNQADCgcIDAABAAAAAA==.Rabbitslayer:BAAANQAECgYICAAAAA==.Raegon:BAAANQAFFAMIAwAAAA==.Raelix:BAAANQADCgcIBwAAAA==.Ragù:BAAANQADCgEIAQAAAA==.Railak:BAAANQAECgIIAgAAAA==.Raiten:BAAANQADCgYIBwAAAA==.Rakan:BAAANQADCgMIAwAAAA==.Raknarto:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Rakthyr:BAAANQADCgEIAQAAAA==.Rampage:BAAANQAFFAIIAgAAAA==.Rapidhidder:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Raptor:BAAANQADCgYIBgAAAA==.Raserage:BAAANQADCgYIBgAAAA==.Rashadevanz:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Rashmi:BAAANQAECgYICQAAAA==.Rastt:BAAANQADCggICAAAAA==.Rathina:BAAANQADCgUIBQAAAA==.Rayjizzle:BAAANQAECggIDQAAAA==.Raynfahl:BAAANQADCgcICQAAAA==.Raynscale:BAAANQADCgQIBAABNQADCgcICQABAAAAAA==.Razual:BAAANQADCgYICwAAAA==.',
Re='Reaperexarch:BAAANQAECgYIDAAAAA==.Reberawr:BAAANQADCgQIBAAAAA==.Recount:BAAANQADCggIDQAAAA==.Redseal:BAAANQADCgcICAAAAA==.Reighart:BAAANQAECgQIBQAAAA==.Relisse:BAAANQADCgUIBQAAAA==.Relmac:BAAANQAECgIIAgABNQAECgUIBQABAAAAAA==.Relusions:BAAANQAECgEIAQAAAA==.Relyne:BAAANQADCggICAAAAA==.Rendandan:BAAANQAECgEIAQAAAA==.Replaced:BAAANQABCgEIAQAAAA==.Reposado:BAAANQADCgMIAwAAAA==.Retrdin:BAAANQADCgcIDgAAAA==.Revastrana:BAAANQAECgEIAQAAAA==.Revelare:BAAANQADCgIIAgAAAA==.Revien:BAAANQADCgMIAwAAAA==.',
Rh='Rhaazt:BAAANQADCgYIBgAAAA==.Rhundus:BAAANQADCgYICAAAAA==.Rhyenmonk:BAAANQADCggIEAAAAA==.',
Ri='Riceshower:BAAANQADCggIDAAAAA==.Riftah:BAAANQAECgEIAQAAAA==.Rikdk:BAAANQAECgQIBAAAAA==.Rimáth:BAAANQADCggIAgABNQAECgYICgABAAAAAA==.Riptide:BAAANQADCgEIAQAAAA==.Rispekt:BAAANQADCgQIBwAAAA==.Risqit:BAAANQAECgIIAgAAAA==.',
Ro='Rodazshan:BAAANQADCggIEAAAAA==.Rogueirl:BAAANQADCgIIAgAAAA==.Roguespierre:BAAANQADCgUIBwAAAA==.Roleswapped:BAAANQADCgIIAgAAAA==.Roobks:BAAANQADCgUIBQAAAA==.Rothien:BAAANQADCggICAAAAA==.Rowanne:BAAANQADCgUIBQAAAA==.',
Ru='Rubberduck:BAAANQAECgUIBwAAAA==.Rumbrodil:BAAANQAECgQIBQAAAA==.Rumplelock:BAAANQADCgYIBgAAAA==.Ruweyna:BAAANQAECgIIAgAAAA==.',
Ry='Rykkar:BAAANQADCgcIDQAAAA==.Ryùù:BAAANQADCgEIAQAAAA==.',
['Rì']='Rìsky:BAAANQAECgQIBQAAAA==.',
Sa='Sabertvvth:BAAANQADCgQICAAAAA==.Sadgetank:BAAANQADCgYIBgAAAA==.Sageth:BAAANQAECggIDgAAAA==.Saiso:BAAANQAECgEIAgAAAA==.Samasamu:BAAANQADCgMIAwAAAA==.Sammerhammer:BAAANQADCgYIDQAAAA==.Sanarindar:BAAANQADCgMIAwAAAA==.Sangluten:BAAANQADCgUICAAAAA==.Sangoine:BAAANQADCgQIBwAAAA==.Sanguinoux:BAAANQADCgYICwAAAA==.Sanidar:BAAANQADCggIEwAAAA==.Sannic:BAAANQAECgMIBAAAAA==.Santhiels:BAAANQADCgcIDAAAAA==.Sarashel:BAAANQADCgYICwAAAA==.Sayanim:BAAANQADCggICAABNQAECggIDwABAAAAAA==.',
Sb='Sbashem:BAAANQADCgYIBgAAAA==.',
Sc='Scartissue:BAAANQADCggICAAAAA==.Schloop:BAAANQADCgcIDQAAAA==.Scoobsz:BAAANQABCgIIAgAAAA==.Scottdizzle:BAAANQAECgYIBAAAAA==.Scourgeghoul:BAAANQAECgcIDQAAAA==.Scourgevoodz:BAAANQADCgQIBAAAAA==.Scowarr:BAAANQAECgIIAgAAAA==.',
Se='Sebb:BAAANQAFFAEIAQAAAA==.Seconddps:BAAANQAFFAEIAQAAAA==.Sededia:BAAANQADCgYIBwAAAA==.Seen:BAAANQADCgYIBgAAAA==.Seinodorei:BAAANQAECgMIAwAAAA==.Sekscalibur:BAAANQADCgEIAQABNQADCggIEQABAAAAAA==.Selita:BAAANQADCgUIBQAAAA==.Semter:BAAANQAECgQIBQAAAA==.Sennîn:BAAANQAECgMIAwAAAA==.Serelium:BAAANQAECgIIAgAAAA==.Sesharr:BAAANQADCgYIBwABNQAECgQIBAABAAAAAA==.Sesticles:BAAANQAECgEIAQAAAA==.Sevarnha:BAAANQADCgYIBgAAAA==.Seysa:BAAANQADCgcIBwAAAA==.',
Sh='Shackakhan:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Shalynn:BAAANQADCgYICAAAAA==.Shamantha:BAAANQAECgEIAQAAAA==.Shamoon:BAAANQADCgUIBQAAAA==.Shampagnee:BAAANQADCgYIBgAAAA==.Shamtrolli:BAAANQADCgYICwAAAA==.Shapasmash:BAAANQAECgMIAwAAAA==.Shayko:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Shayo:BAAANQADCgcIDQAAAA==.Sheash:BAAANQAECgQIBAABNQAECgcIBwABAAAAAA==.Shebaldbro:BAAANQAECgUIBQAAAA==.Sheem:BAAANQAECgEIAgAAAA==.Sheepmedaddy:BAAANQAECgIIAgAAAA==.Sheepshock:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.Sherloctopus:BAAANQAECgIIAgAAAA==.Shimply:BAAANQADCggICQAAAA==.Shinmasta:BAAANQAECggIDQAAAA==.Shinrogue:BAAANQAECgQIBwAAAA==.Shippujinlai:BAAANQAECgYICAAAAA==.Shiraki:BAAANQADCgQIBAABNQADCggIDgABAAAAAA==.Shirro:BAAANQADCggICAAAAA==.Shivaah:BAAANQADCgYIBgAAAA==.Shiñe:BAAANQADCgIIAgAAAA==.Shmo:BAAANQADCgIIAgAAAA==.Shmoopy:BAAANQADCgUICAAAAA==.Shoktherapy:BAAANQAECggICAAAAA==.Shoktyz:BAAANQADCggICAAAAA==.Shortbread:BAAANQAECgEIAQAAAA==.Shortfoot:BAAANQAECgEIAQAAAA==.Shuddaran:BAAANQADCggIDgAAAA==.Shyahman:BAAANQADCggIDgAAAA==.Shyka:BAAANQAECgQIBAAAAA==.Shü:BAAANQADCgYIBgAAAA==.',
Si='Sicphuc:BAAANQAECgIIAgAAAA==.Sieganakh:BAAANQAECgEIAQAAAA==.Sigfodr:BAAANQADCgYICwABNQADCgUIBQABAAAAAA==.Simdh:BAAANQAECgMIBAABNQAFFAMIBAABAAAAAA==.Simivoke:BAAANQAFFAMIBAAAAA==.Simpculture:BAAANQADCgMIAwAAAA==.Simpledawn:BAAANQADCgYICgABNQAECgQIBAABAAAAAA==.Simplefel:BAAANQAECgQIBAAAAA==.Simplestorm:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Sineplil:BAAANQAECggIDgAAAA==.Sinesta:BAAANQADCggICgAAAA==.Sioldor:BAAANQAFFAMIBAAAAA==.',
Sk='Skimnms:BAAANQAECgUIBQAAAA==.Sklornham:BAAANQADCgEIAQAAAA==.Skullcrusher:BAAANQADCgQIBAAAAA==.Skysader:BAAANQAECgEIAQAAAA==.',
Sl='Slaanesh:BAAANQADCgcIDQAAAA==.Slamywhamies:BAAANQADCgcIBwAAAA==.Sleeptokenn:BAAANQADCgUICQAAAA==.Slokni:BAAANQAECgIIAgAAAA==.Slyxan:BAAANQAECgMIAwAAAA==.',
Sm='Smackmaster:BAAANQADCgUIBgAAAA==.Smitez:BAAANQABCgIIAgAAAA==.Smokaajoka:BAAANQADCgIIAgAAAA==.',
Sn='Sneakybiskit:BAAANQADCggICQABNQAECgIIAgABAAAAAA==.Snowbeerd:BAAANQAECgIIAgAAAA==.Snowpup:BAAANQADCgYIDAAAAA==.Snowymess:BAAANQAECgYIBgAAAA==.',
So='Socrates:BAAANQADCggICAAAAA==.Sofakingjay:BAAANQADCgYIBgAAAA==.Sonofanarchy:BAAANQADCgEIAQAAAA==.Sophique:BAAANQAECgMIAwAAAA==.Sosonie:BAAANQADCgYIDAAAAA==.Soulreaker:BAAANQADCggICAAAAA==.Soulshine:BAAANQADCggIDwAAAA==.Soulyssra:BAAANQAECgQIBQAAAA==.Sourrpatch:BAAANQAECgEIAQAAAA==.Sovereígnty:BAAANQADCgYICwAAAA==.',
Sp='Spacedout:BAAANQAECgQIBAAAAA==.Spacemonk:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.Spacetotem:BAAANQAECgQIBAAAAA==.Spamalotz:BAAANQAECgEIAQAAAA==.Sparey:BAAANQADCgIIAgAAAA==.Sparkledots:BAAANQADCggICAAAAA==.Spex:BAAANQADCgcIBwABNQAECgYIDAABAAAAAA==.Spongiform:BAAANQAECgIIAgAAAA==.Springz:BAAANQAFFAMIBAAAAA==.Spritzii:BAAANQAECgEIAQAAAA==.',
Sq='Squeeia:BAAANQAECgIIAgAAAA==.Squishmellow:BAAANQAECgQIBwAAAA==.Squishytankz:BAAANQAECgEIAQAAAA==.',
St='Stansmith:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.Statement:BAAANQADCgYICwAAAA==.Stealthish:BAAANQADCgMIAwAAAA==.Steinenchump:BAAANQABCgIIAgAAAA==.Stoicsavage:BAAANQAECgYICgAAAA==.Stoke:BAAANQADCggICAAAAA==.Stranger:BAAANQAECgEIAQAAAA==.Stsimplicius:BAAANQAECgMIAwAAAA==.',
Su='Sugàrbear:BAAANQAECgEIAQAAAA==.Sunderd:BAAANQADCgUIBwAAAA==.Superkow:BAAANQADCgEIAQAAAA==.',
Sw='Swayzy:BAAANQADCgQIBAAAAA==.Swegbert:BAAANQAECgcIDAAAAA==.Swiffy:BAAANQADCggIDAAAAA==.Swishboom:BAAANQAECgYIBwAAAA==.Swisscheesé:BAAANQAECgMIAwAAAA==.Swxggin:BAAANQADCgMIAwAAAA==.',
Sy='Syfora:BAAANQAECgEIAQAAAA==.Syl:BAAANQADCgYIBgAAAA==.Sylvoor:BAAANQADCgUIBQAAAA==.Sylzurena:BAAANQAECgIIAgAAAA==.Synblade:BAAANQADCggIDgAAAA==.Syphaá:BAAANQAECgUICQAAAA==.Syssaria:BAAANQADCggIDgAAAA==.',
['Sá']='Sáphira:BAAANQAECgEIAQAAAA==.',
['Sí']='Sígíl:BAAANQADCgYIBgAAAA==.',
['Sî']='Sîxseven:BAAANQAECgIIAgAAAA==.',
Ta='Tacobelf:BAAANQADCgQIBAAAAA==.Tacochorizo:BAAANQAECgYICgAAAA==.Tacotorta:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Tahnaa:BAAANQAECgEIAgAAAA==.Taldorian:BAAANQAECgEIAQAAAA==.Talea:BAAANQAECgEIAQAAAA==.Taleraz:BAAANQADCggIFgAAAA==.Talio:BAAANQAECgIIAgAAAA==.Talishe:BAAANQADCgIIAgAAAA==.Tanhunter:BAAANQAECgYIAQAAAA==.Tanknite:BAAANQADCgYICAAAAA==.Tauk:BAAANQADCgYICwAAAA==.Taur:BAAANQADCgQIBAAAAA==.Taxadin:BAAANQAECgQIBAAAAA==.',
Te='Tearius:BAAANQADCgcIDQAAAA==.Tekdar:BAAANQAECgEIAQAAAA==.Teldreg:BAAANQAECgEIAQAAAA==.',
Th='Thadamaja:BAAANQAECgQIBQAAAA==.Thassurian:BAAANQAECgIIAgAAAA==.Thechiefsham:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Thedevilscry:BAAANQAECgUIBwAAAA==.Thefooknpope:BAAANQABCgIIAgAAAA==.Thejimmykp:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Thejimmyks:BAAANQAECgUICAAAAA==.Therus:BAAANQADCggIDQAAAA==.Thescotsman:BAAANQAECgQICAAAAA==.Thiccroy:BAAANQAECgMIAwAAAA==.Thindragosa:BAAANQAECgcIBwAAAA==.Thisisfartaa:BAAANQAECgYICAAAAA==.Thistleus:BAAANQABCgMIAwAAAA==.Thitanite:BAAANQAECgcIDQAAAA==.Thorrash:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Thothiana:BAAANQAECgQIBAAAAA==.Threefíngers:BAAANQADCgcICAAAAA==.Thunderhorse:BAAANQADCgYIDAABNQADCggIDgABAAAAAA==.Thünderthigh:BAAANQADCggIDgAAAA==.',
Ti='Tigrin:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Tilorias:BAAANQADCgMIAwAAAA==.Tirenis:BAAANQAECgIIAwAAAA==.Titanight:BAAANQADCgcIDQABNQAECgcIDQABAAAAAA==.',
To='Tokugawa:BAAANQAECgMIAwAAAA==.Tomidan:BAAANQAECgEIAQAAAA==.Tomiie:BAAANQAECgUIBQAAAA==.Tomo:BAAANQAECgQIBwAAAA==.Tonese:BAAANQADCgYIBgAAAA==.Tonorian:BAAANQAECgQIBAAAAA==.Tontsuoo:BAAANQAECggIDgAAAA==.Tookahh:BAAANQAECgQIBAAAAA==.Toolongdruid:BAAANQAECgQIBAAAAA==.Toosieslide:BAAANQADCgYIBgAAAA==.Toroaki:BAAANQAECgEIAQAAAA==.Torrence:BAAANQADCggIEQAAAA==.Torvalas:BAAANQADCggIDgAAAA==.Totemloveer:BAAANQADCggICAAAAA==.Toughshíft:BAAANQADCgYICAAAAA==.',
Tr='Traklok:BAEANQAECgYIBwAAAA==.Trakspect:BAEANQADCggICAABNQAECgYIBwABAAAAAA==.Traprhd:BAAANQADCgcIDQAAAA==.Trepania:BAAANQADCggIDgAAAA==.Treydog:BAAANQADCggIDAAAAA==.Trichosis:BAAANQAECgIIAgAAAA==.Trilais:BAAANQADCggIDgAAAA==.Trillforpres:BAAANQADCgIIAgAAAA==.Trollfoo:BAAANQAECgcIDAAAAA==.Trustar:BAAANQAECgIIAgAAAA==.',
Tu='Tukohama:BAAANQAECgQIBAAAAA==.Tulugak:BAAANQADCgQIBAAAAA==.Turkëy:BAAANQADCggIEAAAAA==.Tuskrot:BAAANQADCgYIBgAAAA==.',
Ty='Tyielen:BAAANQADCgMIBQAAAA==.Tyrandus:BAAANQAECgQIBgAAAA==.',
['Tá']='Tárgaryén:BAAANQADCgYIBgAAAA==.',
['Tè']='Tèmutank:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.',
['Tó']='Tópluck:BAAANQAECgcIDQAAAA==.',
Ub='Ubuntuu:BAAANQADCgQIBAAAAA==.',
Uh='Uhej:BAAANQAECgIIAgAAAA==.',
Ul='Ulrius:BAAANQADCggICAAAAA==.',
Un='Undeadjoe:BAAANQADCgUIBQAAAA==.Undyingchaos:BAAANQAECgMIAwAAAA==.Unholypaine:BAAANQADCgYICQAAAA==.Unndyne:BAAANQAECgMIBAAAAA==.Unpoquito:BAAANQADCgUIBQAAAA==.Unyunsuki:BAAANQADCgUIBQAAAA==.Unzipzippin:BAAANQAECgYIBwAAAA==.',
Va='Valarrhea:BAAANQADCgYIBgAAAA==.Valdorok:BAAANQADCgQIBQAAAA==.Valeaux:BAAANQADCgcIBwAAAA==.Valee:BAAANQADCggIDgAAAA==.Valeegos:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Valeryth:BAAANQADCggIDgAAAA==.Valhalladin:BAAANQADCgcIBwAAAA==.Valicore:BAAANQADCggIDgAAAA==.Validori:BAAANQAECgEIAQAAAA==.Valinn:BAAANQADCgcIDgABNQAECggIDwABAAAAAA==.Vallentha:BAAANQADCggIEAAAAA==.Valoosh:BAAANQADCgUIBwAAAA==.Varencia:BAAANQADCgYIBgAAAA==.Vashdavoker:BAAANQAFFAMIAwAAAA==.Vashmonk:BAAANQAFFAMIBAAAAA==.Vatonacho:BAAANQAECgMIAwAAAA==.',
Ve='Vedakia:BAAANQAECgMIAwAAAA==.Venadria:BAAANQAECgQIBQAAAA==.Veraphage:BAAANQAECgMIAwAAAA==.Vesttii:BAAANQADCgYICwAAAA==.Vetna:BAAANQAECgMIAwAAAA==.Vexare:BAAANQADCgQIBgAAAA==.',
Vi='Viceviscera:BAAANQAECgcICwAAAA==.Victaroma:BAAANQADCgQIBQAAAA==.Vileshaman:BAAANQADCgYICwAAAA==.Vilt:BAAANQAECgIIAgAAAA==.Vinem:BAAANQABCgQIAgAAAA==.Vivikree:BAAANQADCggIDgAAAA==.',
Vl='Vladryk:BAAANQAECgQIBAAAAA==.',
Vo='Voldún:BAAANQAECgYICQAAAA==.Voodoolin:BAAANQADCgMIAwAAAA==.Voojin:BAAANQAECgQIBQAAAA==.',
Vu='Vuluw:BAAANQAECgQIBAAAAA==.',
Vy='Vyndrokos:BAAANQADCgUIBgABNQADCggIDgABAAAAAA==.Vynitha:BAAANQAECgYICQAAAA==.Vyrex:BAAANQAECgEIAQAAAA==.',
['Vá']='Váltiell:BAAANQAECgIIAgAAAA==.',
Wa='Wacky:BAAANQAFFAMIBAAAAA==.Wahnthac:BAAANQADCgcIDQAAAA==.Walls:BAAANQADCggIDgAAAA==.Waltr:BAAANQAECgQIBAAAAA==.Wanhayda:BAAANQAECgIIAgAAAA==.Warjoe:BAAANQAECgEIAQAAAA==.Warloko:BAAANQADCgYICwAAAA==.Warmi:BAAANQADCgYIDAAAAA==.Washuwa:BAAANQADCgMIAwAAAA==.Washzoo:BAAANQAECgIIAgAAAA==.Waterentul:BAAANQABCgQIBAABNQAECgYICQABAAAAAA==.',
We='Weldras:BAAANQADCgEIAQAAAA==.Weneedalust:BAAANQADCggICwAAAA==.Wezleysnipez:BAAANQAECgMIAwAAAA==.',
Wh='Whampickle:BAAANQAECgEIAQAAAA==.Whirlyshield:BAAANQADCgcIBwAAAA==.Whirlystorm:BAAANQAECgQICAAAAA==.Whispyr:BAEANQAFFAIIAgAAAA==.Whitearms:BAAANQAFFAMIBAAAAA==.Whitepally:BAAANQAECgYIBgABNQAFFAMIBAABAAAAAA==.',
Wi='Wibplea:BAAANQADCgcIDQAAAA==.Wideclyde:BAAANQAECgEIAQAAAA==.Wildkaren:BAAANQADCgYIBgAAAA==.Willa:BAAANQADCgYIDAAAAA==.Willieloman:BAAANQADCgMIAwAAAA==.Windish:BAAANQADCgYIBgAAAA==.Windy:BAAANQADCggIDQAAAA==.Wintermourne:BAAANQADCgMIAwAAAA==.Wizrdtamer:BAAANQAECgMIAwAAAA==.',
Wr='Wrathmon:BAAANQADCgYIBgAAAA==.Wrekkd:BAAANQAECgMIAwAAAA==.',
Wt='Wtfisblood:BAAANQADCgMIAwAAAA==.Wtftankyou:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
Xa='Xaladria:BAAANQADCggIDgAAAA==.Xanarïs:BAAANQAECgUIBwAAAA==.Xandorel:BAAANQAECgYICgAAAA==.Xantar:BAAANQAECgEIAQAAAA==.',
Xe='Xelance:BAAANQAECgUIBgAAAA==.',
Xi='Xindr:BAAANQAECgYICQAAAA==.',
Xp='Xplit:BAAANQAECgQIBQAAAA==.',
Xq='Xq:BAAANQADCgYICwAAAA==.',
Xy='Xyal:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Xyshina:BAAANQAECgEIAQAAAA==.',
Ya='Yahanna:BAAANQAECgMIAwAAAA==.Yajirobi:BAAANQAECgMIBQAAAA==.Yakira:BAAANQADCggIDQAAAA==.Yakuza:BAAANQAECgYICgABNQAECggIDgABAAAAAA==.Yamaotoko:BAAANQAECgIIAgAAAA==.Yaola:BAAANQADCgQIBAAAAA==.',
Yi='Yiikers:BAAANQADCgYIBgABNQAECgMIBQABAAAAAA==.Yirklu:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.',
Yl='Ylizar:BAAANQAECgYICAAAAA==.',
Yo='Yogalight:BAAANQAECgIIAgAAAA==.Yoloswagin:BAAANQAECgEIAQAAAA==.Youpí:BAAANQAECgUIBwAAAA==.',
Yr='Yrella:BAEANQADCggIDQAAAA==.',
Yt='Ytannonx:BAAANQADCggIEQAAAA==.',
Yu='Yukianesa:BAAANQAFFAIIAwAAAA==.Yumdemoncum:BAEANQAECgcICwAAAA==.Yurì:BAAANQADCgcIEAAAAA==.',
Za='Zaemer:BAAANQAECgcIDQAAAA==.Zahkhan:BAAANQADCggICAAAAA==.Zappyfox:BAAANQAECgIIAgAAAA==.Zapzap:BAAANQADCggIDgAAAA==.Zareine:BAAANQAECgQIBAAAAA==.Zaroff:BAAANQABCgQIBAABNQADCgYICwABAAAAAA==.Zaromi:BAAANQADCgIIAgAAAA==.Zave:BAAANQADCggIDgAAAA==.Zayvion:BAAANQAECgMIAwAAAA==.Zaze:BAAANQAECgEIAQAAAA==.Zazekhan:BAAANQADCgQIBAAAAA==.',
Zd='Zdpspej:BAAANQAECgcIDQABNQAECgcIDQABAAAAAA==.',
Ze='Zehn:BAAANQAECgEIAQAAAA==.Zekbrew:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Zekio:BAAANQADCgMIAwAAAA==.Zelgaras:BAAANQADCgYIBgAAAA==.Zendraq:BAAANQADCgcIDQAAAA==.Zeroic:BAAANQADCgIIAgAAAA==.Zeroism:BAAANQAECgMIAwAAAA==.Zeropassion:BAAANQAECgQIBAABNQAECgcICQABAAAAAA==.',
Zi='Zigrond:BAAANQAECgEIAQAAAA==.Zipzopzap:BAAANQADCgMIAwAAAA==.',
Zn='Znx:BAAANQADCgcIBwAAAA==.',
Zo='Zolash:BAAANQADCgQIBAAAAA==.Zolero:BAAANQADCgMIAwAAAA==.Zonkers:BAAANQADCgEIAQAAAA==.Zoraina:BAAANQADCgUIBQAAAA==.Zozoowo:BAAANQADCgYIDAAAAA==.',
Zu='Zulzug:BAAANQAECgQIBAAAAA==.',
Zy='Zyberia:BAAANQAECgEIAQAAAA==.',
['Zâ']='Zâîdêr:BAAANQADCgcIDAAAAA==.',
['Zê']='Zêriah:BAAANQADCggIDwAAAA==.',
['Àz']='Àzir:BAAANQADCggICAAAAA==.',
['Ãa']='Ãang:BAAANQADCggIDgAAAA==.',
['Åk']='Åkeno:BAAANQADCgcICQAAAA==.',
['Çh']='Çholula:BAAANQADCgcIBwAAAA==.',
['Çë']='Çëll:BAAANQADCgYIBgAAAA==.',
['Ép']='Épsilon:BAAANQADCgYIDAAAAA==.',
['Öb']='Öbsessed:BAAANQADCgUICQAAAA==.',
['Ùn']='Ùnbreakabull:BAAANQADCgcIBwAAAA==.',
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
