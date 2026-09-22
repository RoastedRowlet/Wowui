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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Balance','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Druid-Restoration','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-BeastMastery','Warrior-Protection','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Shaman-Enhancement','Warlock-Affliction','Druid-Guardian',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aalen:BAABNQAECoEhAAMBAAgKjxCoGQAQAgABAAgKjxCoGQAQAgACAAQKlwj8jQCnAAAAAA==.',
Ab='Aby:BAAANQAECgQJBgAAAA==.',
Ac='Achooah:BAABNQAECoEkAAIDAAkKuyTzAgC5AwADAAkKuyTzAgC5AwAAAA==.Acturus:BAAANQAECgMJAwAAAA==.',
Ad='Adekeh:BAAANQADCgcJCQAAAA==.',
Ae='Aela:BAAANQAECgcIEwAAAA==.Aenie:BAAANQAECgEJAQAAAA==.Aerose:BAAANQAECgUJCAAAAA==.Aethelia:BAAANQAECgMJAwAAAA==.',
Ak='Aki:BAAANQAECgYICgAAAA==.Akie:BAAANQADCggIDgABNQAECgYICgAEAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgIIAwAEAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQAECgQIAwABNQAFFAMJBAAEAAAAAA==.Alumeena:BAAANQADCggJFAAAAA==.Aléx:BAAANQADCgYJBgAAAA==.',
Am='Amelei:BAABNQAECoEYAAIFAAgKhSHEEAAFAwAFAAgKhSHEEAAFAwAAAA==.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgQJBQAAAA==.Amyquivers:BAAANQAECgQJBAAAAA==.',
An='Anami:BAAANQADCgEIAQAAAA==.Andarieal:BAAANQAECgUICwAAAA==.Androlas:BAAANQADCgQIBAAAAA==.Angeldown:BAAANQADCgQIBAAAAA==.Angelgrinder:BAAANQADCgUJBQABNQADCggIEwAEAAAAAA==.Ankhie:BAAANQAECgcIBwAAAA==.Ankhling:BAAANQAECgYIDgABNQAECgcIBwAEAAAAAA==.Annahlia:BAAANQADCgQIBAAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQADCgYIHwAAAA==.',
Ar='Aralye:BAAANQAECgQIBQAAAA==.Armsop:BAAANQADCgUICgAAAA==.Armîda:BAAANQAECgUJCwAAAA==.Arnika:BAAANQAECgUJDQAAAA==.Arvalyn:BAAANQAECgQICQAAAA==.',
As='Ashlien:BAAANQADCgQJBAAAAA==.Astralvoid:BAAANQAECgYIDwAAAA==.Asuya:BAAANQADCgYICgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQADCggJCQAAAA==.',
Au='Aus:BAAANQADCggJGAABNQAECgcJGAAGAHAYAA==.',
Av='Avakai:BAAANQADCgQJBwAAAA==.Avawar:BAAANQABCgIJAgAAAA==.',
Ax='Axazon:BAABNQAECoEYAAIGAAcKcBiHWQD0AQAGAAcKcBiHWQD0AQAAAA==.Axellered:BAAANQADCgQJBQAAAA==.',
Az='Azark:BAAANQAECgMJBAAAAA==.Azzerria:BAAANQAECgQJBQAAAA==.',
Ba='Bartholoméw:BAAANQAECggJDwAAAA==.Bascus:BAAANQAECgMJBAAAAA==.Bassuu:BAAANQAECgYJCgAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQADCgYIBwAAAA==.Belfør:BAAANQAECgQJCgAAAA==.Bellius:BAAANQAECgUJCQAAAA==.Bennissia:BAAANQADCggJDwAAAA==.Bettiepage:BAAANQABCgMIAwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQICAAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bj='Björk:BAAANQADCgYJBgAAAA==.',
Bl='Blaids:BAAANQABCgEIAQAAAA==.Blaixava:BAAANQADCgYIDAAAAA==.Blazefury:BAAANQAECgYIDwAAAA==.Blueyez:BAAANQADCgcICgAAAA==.',
Bo='Bobsalami:BAAANQADCgUJCwAAAA==.Bophedese:BAAANQADCgEIAQAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAABNQAECoEZAAIHAAgKTxXJIwBHAgAHAAgKTxXJIwBHAgAAAA==.Boyz:BAAANQADCggIDgAAAA==.',
Br='Brannflake:BAAANQADCgYIDQABNQAECgcJDwAEAAAAAA==.Brealia:BAAANQADCgQIBAABNQAECgUJBwAEAAAAAA==.Brewkong:BAEANQAECgIJBAAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAABNQAECoEaAAIIAAkKNx5qLAALAwAIAAkKNx5qLAALAwAAAA==.Brutalious:BAAANQADCggIEwAAAA==.Bruutii:BAABNQAECoEhAAIJAAkKjBhrMACoAgAJAAkKjBhrMACoAgAAAA==.',
Bu='Bubbleandrun:BAAANQAECgUICwAAAA==.Bubbleblast:BAAANQABCggJDAAAAA==.Buckannon:BAAANQAECgMJAwABNQAECgUJCgAEAAAAAA==.Buckaroo:BAAANQAECgQIBAABNQAECgUJCgAEAAAAAA==.Buckcherry:BAAANQAECgUJCgAAAA==.Bulvaan:BAAANQAECgQIBwAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCggIDgAAAA==.',
Ca='Caell:BAAANQAECgUIBwAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAAANQAECgUJBwAAAA==.Cannoneer:BAAANQAECgQJBAABNQAECggIHwAHAEkdAA==.Cannonia:BAABNQAECoEfAAMHAAgKSR2FFgC3AgAHAAgKSR2FFgC3AgAKAAEKvBgGkgBBAAAAAA==.Cantdance:BAAANQADCgQJCAAAAA==.Cantora:BAAANQAECgEIAQAAAA==.Carlyy:BAAANQADCgUJBQABNQAECgUIBgAEAAAAAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQAECgIJBAAAAA==.',
Ce='Cedroes:BAABNQAECoEVAAIGAAUKoRMfnQAzAQAGAAUKoRMfnQAzAQAAAA==.Celandine:BAAANQAECgIIAgAAAA==.Cerenus:BAAANQAECgYICgAAAA==.',
Ch='Chaoswolf:BAAANQAECgEJAQAAAA==.Cheapthrills:BAAANQAECgIJAgAAAA==.Chickfilafry:BAAANQAECgMJAwAAAA==.Chickfilagal:BAAANQAECgUJBQAAAA==.Chipadip:BAABNQAECoEhAAIHAAgKNyCSEQDrAgAHAAgKNyCSEQDrAgAAAA==.Chiqasaurus:BAAANQAECgUIBgAAAA==.Choasbeast:BAAANQADCgEJAQABNQAECggIEQAEAAAAAA==.',
Ci='Cindoria:BAAANQAECgQJBQAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAAANQAECgYJEAAAAA==.Clolarion:BAAANQADCggJGgAAAA==.',
Co='Coltyn:BAAANQAECgYJDAAAAA==.Contrakt:BAAANQAECgYIDwAAAA==.',
Cr='Crackiechan:BAAANQAECgUJCAAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.',
Cu='Curiel:BAAANQAECgEIAQAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAABNQAECoEhAAMLAAkKvSMvAwCcAwALAAkKvSMvAwCcAwAMAAEKNh7UXwBAAAAAAA==.',
Cy='Cyanos:BAAANQAECgQIBAAAAA==.Cymbre:BAAANQADCggIDgAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAAANQAECgYIDwAAAA==.Dakonus:BAAANQADCggJCAAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Daridru:BAAANQADCgYIDAAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkdoctor:BAAANQAECgEJAQAAAA==.Darkhardim:BAAANQAECgEJAQAAAA==.Darkhrt:BAAANQAECgQJBgAAAA==.Darkson:BAAANQADCgYJBgAAAA==.Dawnweaver:BAAANQADCgUIBQAAAA==.Dazedxar:BAAANQAECgcICwAAAA==.',
De='Deado:BAAANQADCgYIBgAAAA==.Deadtotem:BAAANQAECgYJCwAAAA==.Deathdeath:BAAANQAECgMIBQABNQAECggJDAAEAAAAAA==.Deathwavez:BAAANQAECgcJDgAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Deiron:BAAANQADCgIJAgABNQAECggIIQANAL4YAA==.Delirium:BAAANQAECgEJAQAAAA==.Dennis:BAABNQAECoEhAAIOAAgK2iQiBQBDAwAOAAgK2iQiBQBDAwAAAA==.Deosil:BAAANQADCggJCAAAAA==.Departéd:BAECNQAFFIELAAIPAAYKjRokAAAzAgAPAAYKjRokAAAzAgA1AAQKgS4AAw8ACQq+I48AAK0DAA8ACQq+I48AAK0DAA4AAQoeHiBZAEoAAAAA.Deplete:BAAANQADCgIIAgABNQAECgQJBgAEAAAAAA==.Derasia:BAAANQAECgEJAQAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.',
Di='Dianasia:BAAANQADCgUIBQAAAA==.Dingo:BAAANQADCgMIAwABNQAECgkKGwAQAMUiAA==.Dinothunder:BAAANQAECggJEgAAAA==.Dippindots:BAAANQAECgQJBwABNQAECgcJDwAEAAAAAA==.Dirf:BAAANQAECgEJAQAAAA==.Dirtytree:BAAANQADCgYIDAAAAA==.Disc:BAAANQADCgcIDQAAAA==.Discobear:BAACNQAFFIEJAAIRAAUKlBx7AQDYAQARAAUKlBx7AQDYAQA1AAQKgRkAAhEACQqbI+UDAFkDABEACQqbI+UDAFkDAAAA.',
Dk='Dkartha:BAAANQAECgEJAQAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doomui:BAAANQAECgEIAwAAAA==.Dorflundgren:BAAANQAECggJBwAAAA==.Doruh:BAAANQAECgcIDgAAAA==.Dotdragon:BAAANQADCgEIAQAAAA==.',
Dr='Draegon:BAAANQADCgUIBgABNQAECgEJAQAEAAAAAA==.Draemonk:BAAANQADCgYICAABNQAECgEJAQAEAAAAAA==.Draenorious:BAAANQAECgEJAQAAAA==.Dragonix:BAAANQAECgQIBAAAAA==.Dragonrage:BAAANQADCggJCAAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.Druiddrip:BAAANQADCgYJBgABNQADCgYIBwAEAAAAAA==.',
Ds='Dseed:BAAANQADCgMIAwAAAA==.',
Du='Dudris:BAAANQAECgEIAQABNQAECgQJBQAEAAAAAA==.Dumbasmus:BAAANQAECgUJBgAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggJIQAAAA==.',
Ea='Eavie:BAAANQAECgQJBQAAAA==.',
Ed='Ediah:BAAANQAECggJAQAAAA==.Edibleundies:BAAANQADCgMIBQAAAA==.',
Ee='Eeveé:BAAANQAECgQJBwAAAA==.',
El='Electronaut:BAEANQAECgEIAQAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgYJCQAAAA==.Elleria:BAAANQADCgUJBgAAAA==.Ellobb:BAAANQADCgUIBQAAAA==.',
Em='Emeraldstar:BAAANQAECgEJAQAAAA==.',
En='Envelion:BAAANQAECgUJDgAAAA==.',
Er='Erand:BAAANQAECgQICAAAAA==.',
Es='Esvanka:BAAANQAECgcIEAAAAA==.',
Et='Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgIIAwAAAA==.',
Ex='Exfeld:BAAANQABCgMIAwAAAA==.Exoddus:BAAANQAECgQJBAAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQAECgEJAgAAAA==.Faelynatlyf:BAAANQAECgYJEQAAAA==.Falamoto:BAAANQAECgEIAQAAAA==.Fallen:BAAANQAECgUJBQAAAA==.Faltraz:BAAANQADCggICAAAAA==.Fangskin:BAAANQAECgIJBQAAAA==.Fatherdonk:BAAANQAECggIAQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQAECgEJAQAEAAAAAA==.Feyn:BAAANQAECgUJDAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiode:BAAANQAECgYJDgAAAA==.Firsttoaster:BAAANQADCgMIAwAAAA==.',
Fj='Fjall:BAAANQAECgIIAwAAAA==.',
Fl='Flipsmage:BAAANQADCgcIBwAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAAANQAECgUICQAAAA==.Frostea:BAAANQAECgUJDQAAAA==.Frostymidget:BAAANQADCgUJBQAAAA==.Fruitloops:BAAANQAECgMIAwABNQAECgcJDwAEAAAAAA==.',
Fu='Furath:BAAANQADCgIJAgAAAA==.Furrowcious:BAAANQABCgEIAQAAAA==.Fuzybear:BAAANQADCgYIBwABNQADCgcJDQAEAAAAAA==.',
Fy='Fyo:BAABNQAECoEhAAISAAgKByOZBAAtAwASAAgKByOZBAAtAwAAAA==.Fyorin:BAAANQAECgUJCQAAAA==.Fyre:BAAANQADCgMIAwAAAA==.',
['Fä']='Fäyëth:BAAANQAECgQIBAABNQAECgUJCQAEAAAAAA==.',
Ga='Gamerkun:BAAANQAECgQICwAAAA==.Gankz:BAAANQAECgQIBwAAAA==.Gardios:BAAANQADCgUJBQAAAA==.Gargon:BAAANQAECgYJCgAAAA==.Gatchagooner:BAAANQAECgMIBwABNQAECggJBQAEAAAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gh='Ghettofab:BAAANQAECgIJAgAAAA==.',
Gi='Gihum:BAAANQADCgUICwAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAAANQAECgYJCwAAAA==.',
Gj='Gjoflash:BAAANQABCgIIAgAAAA==.Gjolock:BAAANQABCgIIAgAAAA==.',
Gl='Glaizer:BAAANQADCggIDwAAAA==.Glaurung:BAAANQADCgUICgAAAA==.Glencoco:BAAANQADCgYJBgAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.Glue:BAABNQAECoEgAAITAAgKPB8TGwDUAgATAAgKPB8TGwDUAgAAAA==.Glyndoray:BAAANQADCgYJBgAAAA==.',
Gn='Gnomestomper:BAAANQAECgYIDwAAAA==.',
Go='Goldenlotus:BAABNQAECoEhAAMUAAkK9B15EQD7AgAUAAkK9B15EQD7AgATAAIKpQy2ugBzAAAAAA==.Golder:BAABNQAECoEbAAIPAAkK+B81AQBjAwAPAAkK+B81AQBjAwAAAA==.Goldlight:BAAANQADCggJFwAAAA==.Goodshammy:BAAANQAECgYIAwAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgoneion:BAEANQAECgUIDQABNQAECgkJHwAJAA0dAA==.Gortess:BAEBNQAECoEfAAIJAAkKDR3SIwDlAgAJAAkKDR3SIwDlAgAAAA==.',
Gr='Graatch:BAAANQADCgYICwAAAA==.Grandaddy:BAAANQAECgEIAQAAAA==.Greentotems:BAAANQAECgIJBAAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwAAAA==.Gryfalia:BAAANQAECgQIBwAAAA==.',
Gu='Guinevera:BAAANQADCgUJCwAAAA==.Gulo:BAAANQABCgIJAgABNQAECgkKGwAQAMUiAA==.',
['Gó']='Góat:BAABNQAECoEbAAIVAAgKsBGyEQDcAQAVAAgKsBGyEQDcAQAAAA==.',
Ha='Haahoo:BAAANQADCggICAAAAA==.Haart:BAAANQABCgcICQAAAA==.Haavok:BAAANQAECgYJFAAAAQ==.Hadoken:BAAANQAECgYJDQAAAA==.Haist:BAAANQAECgYICQAAAA==.Halenia:BAAANQADCgYJEAAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAAANQAECgYJBwAAAA==.Hamoonraza:BAAANQAECgIJAwAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgUICAAAAA==.Hanske:BAAANQAECgEJAQAAAA==.Happyfeet:BAAANQAECgQIBQAAAA==.Harak:BAAANQAECgQJBQAAAA==.Haranenaea:BAAANQAECgIJAgAAAA==.Harath:BAAANQADCgEIAQAAAA==.Harf:BAAANQAECgEJAQAAAA==.Hatestar:BAAANQAECgEIAgAAAA==.Hauthen:BAAANQAECgYJDAAAAA==.Havoc:BAAANQAECgUJCwAAAA==.',
He='Heliokine:BAAANQAECgEJAQAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAABNQAECoEdAAMFAAkK4h77CQBGAwAFAAkK4h77CQBGAwAGAAEK8AotGgE4AAAAAA==.Hindenburg:BAAANQADCgcIGwAAAA==.',
Ho='Hobemian:BAAANQAECgQJBAAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQAECgYJDQAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQAECgMJAwAAAA==.Hoodsman:BAAANQAECgcJEgAAAA==.Hordebender:BAAANQADCgUIBQAAAA==.Horvon:BAAANQAECgUICQAAAA==.Hound:BAABNQAECoEbAAMQAAkKxSINBABuAwAQAAkKxSINBABuAwAWAAMK4B5LFgD1AAABNQAECgkKGwAQAMUiAA==.',
Hq='Hquartz:BAAANQABCgEIAQAAAA==.',
Hu='Hushh:BAAANQADCgYICAAAAA==.',
Hy='Hyos:BAAANQAECgYICgABNQAECggJIQABAI8QAA==.',
['Há']='Háze:BAAANQAECgUJDAAAAA==.',
['Hâ']='Hâldor:BAAANQAECgEIAQAAAA==.',
Ia='Ianna:BAAANQAECgEIAQABNQAECgIIAgAEAAAAAA==.',
Ib='Ibop:BAAANQADCggJCAABNQAECgYJCgAEAAAAAA==.',
Ic='Icewall:BAAANQAECgEJAQAAAA==.',
Ih='Ihzfrsfld:BAAANQAECgUJCAAAAA==.',
Ik='Ikassei:BAAANQADCgcIBwAAAA==.',
Il='Iledian:BAAANQAECgUJBQAAAA==.Ilexia:BAAANQAECgIJAwAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAAANQAECgUIDAAAAA==.Illidiet:BAAANQAECgEJAQAAAA==.Ilostmybible:BAAANQADCgQIBAAAAA==.',
In='Infierna:BAABNQAECoEWAAIOAAUKRg1fMwA+AQAOAAUKRg1fMwA+AQAAAA==.',
Ir='Ironfistxrio:BAAANQAECgEIAQAAAA==.Ironscale:BAAANQAECgIJAwAAAA==.',
Is='Isath:BAAANQAECgQJBgAAAA==.',
Iw='Iwillblessú:BAAANQAECgQJBAAAAA==.Iwillpeeonu:BAABNQAECoEZAAIBAAgKfiCsCgD/AgABAAgKfiCsCgD/AgAAAA==.',
Ix='Ixix:BAAANQAECgYIDwAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgUIEQAEAAAAAA==.Jalani:BAAANQAECgYIDAAAAA==.Jampire:BAAANQADCgcIBwAAAA==.Jaq:BAAANQADCgYIBgABNQAECgkKGwAQAMUiAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgABNQAECgQJBgAEAAAAAA==.',
Jd='Jdsc:BAAANQAECgQIBAAAAA==.',
Je='Jeffrotull:BAAANQAECgUICgAAAA==.Jentoo:BAAANQAECgcICgAAAA==.Jerg:BAAANQAECgUICwAAAA==.Jerode:BAAANQAECgEJAgAAAA==.Jetpackcat:BAABNQAECoEWAAIXAAkKMRi9AwCfAgAXAAkKMRi9AwCfAgAAAA==.Jexzyn:BAAANQAECgIJAgAAAA==.',
Ji='Jizza:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.',
Jo='Joe:BAAANQADCgYIBgABNQAECgcJDAAEAAAAAA==.Joepiden:BAAANQAECgcJDwAAAA==.Jond:BAAANQAECgcIEwAAAA==.',
Jr='Jrôxs:BAAANQAECgUICQAAAA==.',
Ju='Jubilee:BAAANQAECgcJDgAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.Judgejudo:BAAANQADCgcJCgABNQAECgcIDgAEAAAAAA==.',
['Jí']='Jín:BAAANQADCgUJBQAAAA==.',
Ka='Kadeth:BAAANQAECgEJAQAAAA==.Kagekitsoon:BAAANQADCgUJBQAAAA==.Kahawse:BAAANQADCggICAAAAA==.Kamer:BAAANQAECgYJDgAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kamorita:BAAANQABCgIIAgAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQIDgAAAA==.Karila:BAAANQADCgEJAQABNQAECgUJBwAEAAAAAA==.Katarina:BAABNQAECoEiAAISAAgKiQ3vFAAGAgASAAgKiQ3vFAAGAgAAAA==.Kathu:BAAANQAECgQIBwAAAA==.Kawaii:BAAANQAECgQJCAAAAA==.Kazanot:BAAANQADCgYICQABNQAECgQJBQAEAAAAAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQAECgUICgAAAA==.Kephzax:BAABNQAECoEeAAIIAAgK5Am5mADaAQAIAAgK5Am5mADaAQAAAA==.Kerapac:BAABNQAECoEhAAIKAAkKOA+iLgDuAQAKAAkKOA+iLgDuAQAAAA==.Kezinik:BAACNQAFFIEPAAMKAAYKdxDXBACjAQAKAAYKdxDXBACjAQAHAAEKTAB4EgAnAAA1AAQKgRsAAgoACQqrHzQOAAADAAoACQqrHzQOAAADAAAA.Kezlight:BAAANQAECgUIBQABNQAFFAYJDwAKAHcQAA==.Kezursine:BAAANQAECgMIAwAAAA==.',
Ki='Kireek:BAABNQAECoEZAAIJAAgKcheFRgBOAgAJAAgKcheFRgBOAgAAAA==.Kitas:BAAANQADCgcJDQAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggJEQAAAA==.',
Kn='Knockknocks:BAAANQADCgYICgAAAA==.',
Ko='Koujii:BAABNQAECoEhAAIYAAkKhhtuDwDUAgAYAAkKhhtuDwDUAgAAAA==.',
Kr='Kristyana:BAAANQAECgEIAQABNQAECgIIAwAEAAAAAA==.',
Ks='Ksenja:BAAANQAECgUJBgAAAA==.',
Ku='Kured:BAAANQAECgEJAQAAAA==.Kuum:BAAANQADCggJCgAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEJAQAAAA==.Kylgard:BAAANQADCgUIBAAAAA==.Kyliara:BAAANQABCgQIBwAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylisar:BAAANQABCgUIBgAAAA==.Kylithra:BAAANQABCgMJBQAAAA==.Kylmara:BAAANQADCgQIBgAAAA==.Kylneldth:BAAANQABCgQIBQAAAA==.Kylorend:BAAANQAECgYIDgABNQAECgcJDwAEAAAAAA==.Kylral:BAAANQABCgQIBAAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kysindra:BAABNQAECoEYAAMLAAgKHRkBNgBGAgALAAgKpxYBNgBGAgAMAAMKWxYAMQDdAAAAAA==.Kyutir:BAAANQAECgUIBgAAAA==.Kyuu:BAAANQAECgQJBQAAAA==.Kyygo:BAAANQAECgUJDgAAAA==.',
['Ká']='Kámm:BAAANQAECgQJBwAAAA==.',
['Kè']='Kètåsét:BAAANQADCgQICwAAAA==.',
La='Lacedunlaced:BAAANQADCggIEAABNQAECgcIEgAEAAAAAA==.Ladyneasa:BAAANQAECgYIDgAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAAANQAECgcJDQAAAA==.Lamennais:BAAANQAECgEJAQAAAA==.Lapsene:BAAANQAECgEJAQAAAA==.Lasagna:BAAANQADCgYIDgABNQAECgcJDwAEAAAAAA==.Lavelite:BAAANQADCgIJAwABNQAECgQJBgAEAAAAAA==.Lavendae:BAAANQAECgQJBgAAAA==.Laxus:BAABNQAECoEhAAIZAAgKoSGjEgAPAwAZAAgKoSGjEgAPAwAAAA==.',
Le='Leahpali:BAAANQADCgIIAgAAAA==.Lebronflames:BAAANQAECgUIBQABNQAECgcJDwAEAAAAAA==.Lesath:BAAANQAECgYJEQAAAA==.Lesca:BAAANQADCgYICQABNQAECggIIQAHADcgAA==.Leshalles:BAABNQAECoEWAAMBAAgKlAwgHgDVAQABAAgKlAwgHgDVAQACAAQKkRIJfwDeAAAAAA==.Leviathayne:BAAANQADCgEIAgAAAA==.Levyatan:BAAANQAECgIJAgAAAA==.',
Li='Lianyu:BAAANQAECgEIAQABNQAECgIJAgAEAAAAAA==.Liazel:BAABNQAECoEeAAIZAAgKvCH1FQD3AgAZAAgKvCH1FQD3AgAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCggJGQAAAA==.Limen:BAAANQAECgIJAwAAAA==.Lissael:BAAANQADCggIDgAAAA==.',
Lo='Loaruun:BAABNQAECoEYAAMJAAgKahELYADyAQAJAAgK0RALYADyAQAaAAEKLgiTKgA4AAAAAA==.Locktoasty:BAAANQADCgIJAgABNQAECgEJAQAEAAAAAA==.Loopi:BAAANQAECgUJCAAAAA==.',
Lu='Luminaara:BAAANQADCgIJAgAAAA==.Lunatick:BAABNQAECoEhAAIbAAkKpRgcBQCoAgAbAAkKpRgcBQCoAgAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Læ']='Læris:BAEANQAECgYIBgABNQAECgkJHwAJAA0dAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Madridm:BAAANQADCggICAAAAA==.Maegumi:BAAANQAECgUJCQAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECgUJDAAEAAAAAA==.Magdalyne:BAAANQAECgUJDAAAAA==.Magedudee:BAABNQAECoEhAAIIAAkKtiHoFQBhAwAIAAkKtiHoFQBhAwAAAA==.Magespec:BAAANQAECgEJAwAAAA==.Maghom:BAAANQAECgEIAQAAAA==.Magicdrae:BAAANQADCgMJAwABNQAECgEJAQAEAAAAAA==.Malawoo:BAAANQADCgIJAgAAAA==.Malestrom:BAAANQAECgMJAwAAAA==.Malfei:BAAANQAECgEJAQAAAA==.Manalenna:BAAANQADCgcJCwABNQAECgIIAwAEAAAAAA==.Manate:BAABNQAECoEbAAQNAAkK6hzoBgAJAwANAAkK6hzoBgAJAwAcAAQKVxF6HgD9AAAdAAEKzhVBFgBFAAAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAAANQAECgYJDwAAAA==.Mandori:BAAANQAECgUJCgAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQAECgEJAQAAAA==.Marcushorde:BAAANQAECgIJAgAAAA==.Marineoracle:BAEANQAECgYICwAAAA==.Marter:BAAANQADCgMJBAAAAA==.Martypriest:BAABNQAECoEbAAICAAgK2RTWLwA4AgACAAgK2RTWLwA4AgAAAA==.Maryswanson:BAAANQADCgcIBwAAAA==.Mashal:BAAANQAECgYJCQAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQADCggIHQAAAA==.',
Me='Me:BAAANQAECgQICQAAAA==.Meatsac:BAABNQAECoEYAAIJAAgKaRSJVQAXAgAJAAgKaRSJVQAXAgAAAA==.Mellennah:BAAANQAECgYIDwAAAA==.Melpomenes:BAAANQAECgEIAQAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQADCgUJBQAAAA==.Milk:BAAANQADCggJCAAAAA==.Milkshake:BAAANQABCgIJAgABNQAECgEJAQAEAAAAAA==.Missanthropy:BAAANQADCgcICwAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.',
Mo='Mohpnya:BAAANQADCgYJBwAAAA==.Mongsok:BAABNQAECoEhAAIQAAgKOiH6CgDVAgAQAAgKOiH6CgDVAgAAAA==.Monkmonkmonk:BAAANQAECgMIAwABNQAECggJDAAEAAAAAA==.Moonshíne:BAAANQAECgIIAwAAAA==.Moy:BAAANQAECgUIDAAAAA==.Moÿ:BAAANQAECgYJCAAAAA==.',
Mu='Mumple:BAAANQAECgUICwAAAA==.Murlok:BAAANQAECgUIBwAAAA==.Mustashe:BAAANQADCgUJCAABNQAECgcJDwAEAAAAAA==.',
My='Mynöghra:BAAANQADCgcIDQABNQADCggIEwAEAAAAAA==.Myshak:BAAANQAECgQJBgAAAA==.Mysticsoul:BAABNQAECoEhAAIUAAgK5xprKgBYAgAUAAgK5xprKgBYAgAAAA==.',
['Mè']='Mègàmägë:BAAANQAECgMJBAAAAA==.',
['Mó']='Mórrigan:BAAANQADCgIIAgAAAA==.',
Na='Nadizel:BAAANQAECgEJAQAAAA==.Naglfer:BAAANQAECgQIBAAAAA==.Nanaki:BAAANQADCgUIBQAAAA==.Narisse:BAAANQADCgQIBAAAAA==.Narzud:BAAANQAECgUJBQAAAA==.Nasa:BAAANQADCggIDgAAAA==.Nazmyr:BAAANQAECgcJEAAAAA==.',
Ne='Necrofeelyea:BAAANQAECgEIAQAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAAANQAECgUIBwAAAA==.Niish:BAAANQAECgIJBAAAAA==.',
No='Noani:BAABNQAECoEaAAMCAAgKQiCrEgDrAgACAAgKQiCrEgDrAgABAAEK7wGPYQAdAAAAAA==.Nosretepone:BAAANQAECgQIBAAAAA==.Notgitty:BAAANQABCggIEQAAAA==.Notsu:BAAANQAECgEJAQAAAA==.Novidius:BAAANQAECgYJCgAAAA==.',
Nu='Numkins:BAAANQAECgUJCQAAAA==.',
['Ní']='Níghts:BAAANQAECgUICwAAAA==.',
Oe='Oephelia:BAAANQAECgYICwAAAA==.',
Oj='Ojaru:BAAANQAECgMJBgAAAA==.',
Ol='Olliver:BAAANQADCgUJCAAAAA==.Oloo:BAAANQAECgYJCgAAAA==.',
On='Onlyhams:BAABNQAECoEjAAICAAkK/RFRKQBaAgACAAkK/RFRKQBaAgAAAA==.',
Or='Oras:BAAANQAECgQJBAAAAA==.Orayleina:BAAANQADCgYJHgAAAA==.Oreoero:BAAANQADCggICAABNQAECgUIEAAEAAAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgQIBgABNQAECgcIDgAEAAAAAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgUJCQABNQAECggJDAAEAAAAAA==.Patoot:BAAANQABCgQJBAAAAA==.Paulywag:BAAANQAECgUIBQAAAA==.Paulywog:BAAANQADCgUIBQAAAA==.Pawsed:BAAANQAECgYJCwAAAA==.',
Pe='Perleana:BAAANQAECgYIDwAAAA==.Perra:BAAANQAECgYJEQAAAA==.Petergriffon:BAAANQADCggIGwAAAA==.',
Ph='Philmikehawk:BAABNQAECoEhAAIJAAgKECW1EQBPAwAJAAgKECW1EQBPAwAAAA==.',
Pi='Picklestack:BAAANQAECgQIBAAAAA==.Pikatin:BAAANQADCggICAAAAA==.',
Pl='Platemage:BAAANQAECgcIEgAAAA==.Plavaluguna:BAAANQADCgUIBQAAAA==.',
Ps='Psyk:BAAANQAECggIEQAAAA==.',
Pu='Puding:BAAANQAECgYIDgAAAA==.',
Pw='Pwnykeg:BAAANQAECgEJAQAAAA==.',
Py='Pyixi:BAAANQADCgUIDQAAAA==.',
['Pà']='Pàulywog:BAAANQAECgUJCAAAAA==.',
['Pá']='Páppajohn:BAAANQAECgIJBAAAAA==.',
Qb='Qb:BAABNQAECoEfAAIdAAkKBxbCAwCGAgAdAAkKBxbCAwCGAgAAAA==.',
Qu='Quelenna:BAAANQAECgEJAQAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQAECgEJAQAAAA==.',
Ra='Ragmer:BAAANQAECgYJCgAAAA==.Ragnariuss:BAAANQAECgUJCQAAAA==.Raira:BAAANQAECgIJAwAAAA==.Ravenfeld:BAAANQAECgQJBgAAAA==.Raviolli:BAAANQABCgYIBgAAAA==.Rayos:BAAANQAECggJBQAAAA==.',
Re='Rebelangel:BAAANQADCgQIBAAAAA==.Redbeauty:BAAANQADCgUICgAAAA==.Redvail:BAAANQADCgYIGAAAAA==.Refuting:BAAANQAECgMIAwABNQAECgQIBgAEAAAAAA==.Reivida:BAAANQAECgQJBwAAAA==.Remyxz:BAAANQAECgUICgAAAA==.Renlaut:BAAANQAECgMIBQAAAA==.Renshaibob:BAAANQAECggJAQAAAA==.Reported:BAAANQADCgQIBAABNQAECggIIAAHAC8TAA==.Reprisal:BAABNQAECoEgAAIHAAgKLxNbKQAdAgAHAAgKLxNbKQAdAgAAAA==.',
Rh='Rhapsady:BAAANQADCgYIBgAAAA==.',
Ri='Riffraff:BAAANQAECgMJAwAAAA==.Rioz:BAAANQADCgUIBQAAAA==.Ripbozo:BAAANQAECgYJEQAAAA==.Ritsnimle:BAAANQAECgEIAQAAAA==.',
Ro='Rocknocker:BAABNQAECoEaAAIUAAgK0g4bTQC0AQAUAAgK0g4bTQC0AQAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAABNQAECoEhAAISAAkKEBwYBQAfAwASAAkKEBwYBQAfAwAAAA==.Rowsi:BAAANQADCggJEAAAAA==.Roxene:BAAANQAECgEJAQAAAA==.',
Ru='Rukaza:BAABNQAECoEeAAIeAAgKsCCqCwD3AgAeAAgKsCCqCwD3AgAAAA==.',
Ry='Ryagarz:BAAANQABCgIJAgAAAA==.',
['Rè']='Rènara:BAAANQADCgMIAwAAAA==.',
Sa='Saelyraria:BAAANQAECgIJAwAAAA==.Safijiva:BAAANQAECgQICQAAAA==.Saintrawrs:BAAANQADCgQIBQAAAA==.Saiti:BAABNQAECoEhAAIHAAkK7xx8DwABAwAHAAkK7xx8DwABAwAAAA==.Sanleras:BAAANQAECgYJCgAAAA==.Sanovia:BAAANQADCgYJFwAAAA==.Sanrao:BAAANQADCgUJBQAAAA==.Sarao:BAAANQAECgYJDgAAAA==.',
Sc='Schutzengel:BAAANQADCgcIBwAAAA==.Scoondk:BAAANQAECgEJAQAAAA==.Scuttlebug:BAAANQAECgYJDAAAAA==.Scynthyace:BAABNQAECoEbAAICAAkKGCSAAwCQAwACAAkKGCSAAwCQAwAAAA==.',
Se='Selystina:BAAANQADCggJDgAAAA==.Sensistar:BAAANQAECgYIDgAAAA==.Sephen:BAAANQAECgIJBAAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQADCgYIEQAAAA==.',
Sh='Shadowfacs:BAAANQADCgUJCQAAAA==.Shadowvail:BAAANQAECgEJAgAAAA==.Shakama:BAAANQADCggJHQAAAA==.Shallowhale:BAAANQADCgUJEAAAAA==.Shallzappy:BAABNQAECoEXAAMTAAgKbwtlTADAAQATAAgK/wplTADAAQAfAAYKYgqGFQBvAQAAAA==.Shamander:BAAANQADCgQIBgAAAA==.Shammyfox:BAAANQADCgYIEwAAAA==.Shamuraijack:BAAANQAECgQJCAABNQAECgcJDwAEAAAAAA==.Sharlock:BAAANQABCgYIBgAAAA==.Sheepngone:BAAANQAECgUJBQAAAA==.Shihow:BAAANQABCgYIBgAAAA==.Shooth:BAAANQAECggIDAAAAA==.Shortangry:BAAANQADCggIEAAAAA==.Shrubs:BAAANQAECgQJBgAAAA==.',
Si='Sickminded:BAAANQAECgUJEQAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAAANQAECgUICQAAAA==.Silvain:BAAANQAECgUICwAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQADCgYICgAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAABNQAECoEcAAQLAAgKRxOPZQCWAQALAAYKYhKPZQCWAQAMAAIK9hXeRACNAAAgAAEKfwF4JgAhAAAAAA==.',
Sn='Snokums:BAAANQAECgIIBAAAAA==.Snozzberry:BAAANQAECgEJAQAAAA==.Snykes:BAAANQADCgUJDQAAAA==.',
So='Solaren:BAAANQAECgEIAQAAAA==.Soulsplash:BAAANQADCgUICgAAAA==.',
Sp='Spellsling:BAAANQADCgYIBwAAAA==.Spence:BAABNQAECoEdAAIIAAgKXxlhWgB9AgAIAAgKXxlhWgB9AgAAAA==.',
St='Stackedone:BAAANQABCgUIBgAAAA==.Stankonia:BAAANQADCgMIBQAAAA==.Stanlitwochi:BAABNQAECoEYAAMQAAcKLA5EIACQAQAQAAcKLA5EIACQAQAVAAUKcgOhJwCzAAAAAA==.Starbie:BAAANQADCgUIBQAAAA==.Sticky:BAAANQAECgYJCgAAAA==.Stormkitty:BAAANQAECgQJBgAAAA==.Stout:BAAANQAECgYICwAAAA==.Stubs:BAAANQADCggICAAAAA==.Stumblerut:BAAANQADCgQIBAABNQAECgEJAwAEAAAAAA==.Stuntyron:BAAANQAECgMIAwAAAA==.Stícky:BAAANQADCgQIBAABNQADCggIEwAEAAAAAA==.',
Su='Sums:BAABNQAECoEZAAMLAAkKuBu7KACAAgALAAgKgRq7KACAAgAMAAUKbhy5FwCWAQAAAA==.Sunadrae:BAAANQADCggJCAAAAA==.Sunser:BAABNQAECoEZAAIIAAgKSR9dPwDNAgAIAAgKSR9dPwDNAgAAAA==.Superdruid:BAAANQADCggJDgAAAA==.Supremus:BAAANQAECgEJAgAAAA==.',
Sv='Svetlanka:BAAANQAECgIJBAAAAA==.',
Sy='Sylrêith:BAAANQADCggIHQAAAA==.Sylyndra:BAAANQAECgMICAAAAA==.Syralvia:BAAANQAECgEIAQAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Taltosh:BAAANQAECgEJAQAAAA==.Tardishunter:BAAANQAECgMJAwAAAA==.Tartarrus:BAAANQAECgYJCgAAAA==.Taterthots:BAAANQADCgYICQAAAA==.Taulmäril:BAAANQAECgQJBgAAAA==.',
Te='Tearsofpain:BAAANQAECgMJAwAAAA==.Tearsofrain:BAAANQADCgMIBwAAAA==.Tearsofsolan:BAAANQADCgQJBAAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tellamental:BAEANQABCgIIAwABNQAECggJEgAEAAAAAA==.Tellen:BAEANQAECggJEgAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thdoria:BAAANQABCgQIBAAAAA==.Thequae:BAAANQAECgEJAQAAAA==.Therin:BAAANQADCggJBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thostin:BAAANQADCgcJDAAAAA==.Thotlety:BAAANQAECgIJAgAAAA==.Thrèsh:BAABNQAECoEXAAIhAAkKOQ2kDQC7AQAhAAkKOQ2kDQC7AQAAAA==.Thymara:BAAANQAECgYJEQAAAA==.',
Ti='Tiamot:BAAANQAECgEJAQAAAA==.Ticksndots:BAAANQAECgYICwAAAA==.Tirinas:BAAANQAECgQIBAAAAA==.',
To='Toastragosa:BAAANQAECgEJAQAAAA==.Tobais:BAAANQAECgYICgAAAA==.Tombstone:BAAANQAECgUICwAAAA==.',
Tr='Trapmedaddy:BAAANQADCgMIAwAAAA==.Trigonite:BAAANQADCgUIBQAAAA==.Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQAECgUICQAAAA==.Triqzy:BAAANQAECgQIBAAAAA==.Troikka:BAAANQAECgYIDAAAAA==.Tropicana:BAAANQAECgEIAQAAAA==.Truinnean:BAAANQAECgUIDAAAAA==.',
Tu='Tuarang:BAAANQADCggIDgAAAA==.Turokuruvar:BAAANQAECgEJAQAAAA==.',
Tw='Twinevil:BAAANQAECgEJAQAAAA==.',
Ty='Tynker:BAAANQAECgIIBAAAAA==.Tyravelle:BAAANQADCggIDgAAAA==.',
['Tú']='Túg:BAAANQADCggIDAABNQAECgkJGgAIADceAA==.',
Un='Undousedrice:BAAANQAECgUJBwAAAA==.Unleashes:BAAANQAECgQIBgAAAA==.',
Uz='Uzu:BAAANQADCgUJBwAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQAECgIJAgAAAA==.Valërie:BAAANQAECgcJCwAAAA==.Vanarian:BAABNQAECoEhAAIDAAkKExOCHwByAgADAAkKExOCHwByAgAAAA==.Varaza:BAAANQADCgYICAAAAA==.',
Ve='Velaania:BAAANQAECgUIBwAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQABNQADCgUIBQAEAAAAAA==.Vertaí:BAAANQAECgEJAQAAAA==.Veter:BAAANQAECgUJDwAAAA==.Vexxon:BAAANQAECggIBwABNQAECggJCAAEAAAAAA==.',
Vi='Vibrotron:BAAANQAECgYIDwAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.Virusalert:BAAANQADCgcJDgAAAA==.',
Vo='Voidfire:BAAANQADCgUIBQAAAA==.Voidpera:BAAANQAECgUJBgAAAA==.',
Vu='Vulpics:BAAANQAECgUIEQAAAA==.',
['Vè']='Vèrten:BAAANQADCgYIBgAAAA==.',
Wa='Warexx:BAAANQAECgQJBAAAAA==.Wasupnow:BAAANQAECgYIDQAAAA==.',
We='Weetchdoctah:BAAANQAECgYJCgAAAA==.Weewarrior:BAAANQAECggJCAAAAA==.Wehuttie:BAAANQADCgQIAgABNQAECggIDAAEAAAAAA==.Wenadin:BAAANQAECgIJAgAAAA==.Wetwibution:BAABNQAECoEZAAMGAAgKWAyCbgCxAQAGAAgKWAyCbgCxAQAFAAcK6gmGYAB1AQAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQADCgYIFwABNQADCgYIHwAEAAAAAA==.',
Wi='William:BAAANQAECgIJAgAAAA==.',
Wr='Wrathawk:BAAANQADCgYJBwAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAQABNQAECggJFwATAG8LAA==.',
Xh='Xhii:BAABNQAECoEhAAIWAAgKQSG2AwADAwAWAAgKQSG2AwADAwAAAA==.',
Xi='Xingxong:BAAANQADCgUIBQAAAA==.',
Xu='Xuann:BAAANQAECgMIAwAAAA==.',
Xy='Xykaz:BAABNQAECoEhAAIIAAkKMhdKTACmAgAIAAkKMhdKTACmAgAAAA==.',
Ya='Yanakiria:BAAANQAECgIIAwAAAA==.',
Ye='Yendi:BAAANQAECgYJCAAAAA==.',
Yn='Yngvar:BAAANQAECggJDwAAAA==.',
Yo='Yokira:BAAANQABCggIDgAAAA==.You:BAAANQAECgQIBAAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Za='Zarknoth:BAAANQAECggIEgAAAA==.',
Ze='Zelmancha:BAAANQAECgcIDAAAAA==.Zenkichi:BAAANQADCgYIDgAAAA==.Zephyyra:BAAANQAECgEJAQAAAA==.Zethriel:BAAANQAECgIJBAAAAA==.Zevorra:BAAANQADCgYIBgABNQADCggIHQAEAAAAAA==.',
Zh='Zhealan:BAAANQADCgYJCQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAAANQAECgYJDAAAAA==.Zinarosee:BAAANQADCggJCAABNQAECggIIQANAL4YAA==.Zinathyr:BAABNQAECoEhAAINAAgKvhhBEABTAgANAAgKvhhBEABTAgAAAA==.',
Zo='Zorrita:BAAANQADCgMIBgABNQADCgUJBQAEAAAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgQICAAAAA==.',
Zz='Zzuul:BAAANQAECgYJCgAAAA==.',
['Zý']='Zýe:BAAANQAECgIJBAAAAA==.',
['Æx']='Æxil:BAAANQADCgUJCwAAAA==.',
['Él']='Éleanor:BAAANQAECgYJEAAAAA==.',
['Öh']='Öhai:BAAANQAECgUIBwAAAA==.',
['ßr']='ßröádin:BAAANQADCgMIAwAAAA==.',
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
