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

local lookup = {'Warrior-Arms','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Warlock-Demonology','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Evoker-Augmentation','Shaman-Enhancement','Warlock-Destruction','Mage-Arcane','DeathKnight-Blood','Priest-Discipline','Warlock-Affliction','Druid-Feral','Monk-Mistweaver','Priest-Shadow','Hunter-BeastMastery',}
local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abacas:BAAANQAECgcIEgAAAA==.Abraanu:BAAANQAECgYICgAAAA==.Abrohms:BAAANQAECgMIAwAAAA==.',
Ae='Aeily:BAAANQADCggIFAAAAA==.',
Ag='Agiel:BAAANQADCgYIBgAAAA==.',
Ai='Aiger:BAAANQADCgUIBQAAAA==.Ais:BAAANQAECgYICwAAAA==.Aitsu:BAAANQAECgcIEgAAAA==.Aivy:BAAANQAECgUICQAAAA==.',
Ak='Akkula:BAAANQADCgUIDAAAAA==.Akutagawa:BAAANQADCgcIBwABNQAECgkJGAABAO4jAA==.',
Al='Alexdare:BAAANQAECgUICwAAAA==.Alfadelle:BAAANQAECgUICgABNQAECgYIDAACAAAAAA==.Alicarrdd:BAAANQAECgQIBAAAAA==.Allbeefpatty:BAAANQAECgMIAwAAAA==.Alneeshi:BAAANQAECgYICgAAAA==.Alybella:BAAANQADCggIFAAAAA==.',
Am='Amoriandis:BAAANQADCgMIAwABNQADCggIGQACAAAAAA==.',
An='Ancstrlbower:BAAANQADCgcIEwAAAA==.Anetra:BAAANQADCgYICQAAAA==.Angharad:BAAANQADCgQIBAABNQAECgUIDQACAAAAAA==.Anot:BAAANQAECgYICwAAAA==.Anothai:BAAANQADCgYICQAAAA==.Anton:BAAANQADCggICAABNQAECgMIAwACAAAAAA==.Anutterone:BAAANQAECgQIBAAAAA==.',
Ap='Apsaroke:BAAANQADCgYICwAAAA==.',
Aq='Aqi:BAAANQAECgUIBQAAAA==.',
Ar='Aralle:BAAANQAECgQIBAAAAA==.Aranea:BAAANQAECgIIAgAAAA==.Arclaw:BAAANQADCgEIAQAAAA==.Arin:BAAANQAECgUIBQABNQAECgQIBAACAAAAAA==.Arkadu:BAAANQADCgEIAQAAAA==.Arkys:BAAANQADCgUIBQAAAA==.Arman:BAAANQADCgYIBgAAAA==.Armistice:BAAANQADCgMIAwAAAA==.Arrowyn:BAAANQADCgcIDQAAAA==.',
As='Ashenis:BAAANQABCgQIBAAAAA==.Asphalt:BAAANQAECgMIAwAAAA==.',
At='Attidk:BAAANQAECgUICQAAAA==.',
Au='Augful:BAAANQAECgYICwAAAA==.Auspicious:BAAANQAECgUICwAAAA==.',
Av='Avadin:BAAANQAECgEIAQABNQAECgcIEwACAAAAAA==.Avadinde:BAAANQAECgcIEwAAAA==.Avadingue:BAAANQADCgYIBgABNQAECgcIEwACAAAAAA==.Avadragon:BAAANQAECgEIAgABNQAECgcIEwACAAAAAA==.Aversa:BAAANQADCgEIAQABNQAECgQIBQACAAAAAA==.',
Ay='Aylla:BAAANQAECgIIAgAAAA==.Ayrios:BAAANQADCgEIAQABNQAECgYICwACAAAAAA==.Ayrious:BAAANQAECgYICgAAAA==.',
['Aé']='Aéthric:BAAANQADCgUICAAAAA==.',
Ba='Backather:BAAANQADCgcIBwAAAA==.Backshocks:BAAANQABCgUIBwAAAA==.Bahalanagang:BAAANQADCggIBAAAAA==.Bahrasmyou:BAAANQADCgYIBgAAAA==.Bakkoutou:BAAANQAECgcIEgAAAA==.Baltic:BAAANQAECgEIAQABNQAECgUICAACAAAAAA==.Bambäm:BAAANQADCgYIBgABNQAECgQIBAACAAAAAA==.Bangers:BAAANQAECgEIAQAAAA==.Basix:BAAANQADCgUICgAAAA==.Bastock:BAAANQAECgEIAQAAAA==.',
Be='Beanzmachine:BAAANQAECgEIAQAAAA==.Bearstout:BAAANQADCggIFAAAAA==.Beeans:BAAANQADCgEIAQAAAA==.Beestmaster:BAAANQAECgQICQAAAA==.Belavik:BAAANQAECgYIDgAAAA==.Beowelf:BAAANQAECggIEQAAAA==.Beowulfsson:BAAANQAECgMIAwAAAA==.Bertabeef:BAAANQADCggIFQAAAA==.Betrayar:BAAANQADCgYIBgAAAA==.Bezzert:BAAANQADCgYIBgAAAA==.',
Bh='Bheap:BAAANQAECgcIDgAAAA==.Bheapbheap:BAAANQADCgYIDwAAAA==.',
Bi='Bigchungo:BAAANQADCgUICAAAAA==.Bigcook:BAAANQADCgYIBgAAAA==.Bigpaindk:BAAANQAECgEIAQAAAA==.Bigpaindru:BAAANQADCgcIBwAAAA==.Bigpainpal:BAAANQADCgMIAwAAAA==.Bigshloppy:BAAANQAECgIIAgAAAA==.Billysblade:BAAANQAECgUICQAAAA==.',
Bk='Bkers:BAAANQADCgYIBgAAAA==.',
Bl='Blebipty:BAAANQAECgcIDgAAAA==.Blessyoho:BAAANQADCgYICwAAAA==.Blitzbuster:BAAANQAECgIIAgAAAA==.Blitzy:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Blladee:BAAANQAECgMIAwAAAA==.Bluehorn:BAAANQADCgYIBgAAAA==.Bluekoolaid:BAAANQADCgQIBAAAAA==.Blumpkings:BAAANQADCgMIAwAAAA==.',
Br='Brockly:BAAANQAECgYICgAAAA==.Brolly:BAAANQAECgEIAQAAAA==.Brooski:BAAANQADCgMIAwAAAA==.Brotorious:BAAANQAECgcIBwAAAA==.',
Bu='Bubllz:BAAANQADCgYIBgAAAA==.Bulluptuous:BAAANQAECgUICwAAAA==.Bun:BAAANQABCgMIAgAAAA==.Burkmon:BAAANQAECgEIAQAAAA==.Burret:BAAANQADCgYIEAAAAA==.Butseven:BAAANQAECgMIAwAAAA==.Butterbubble:BAAANQAECgEIAQAAAA==.',
['Bó']='Bótat:BAAANQAECgUICQAAAA==.',
Ca='Cadiron:BAAANQADCgUICwAAAA==.Caedance:BAAANQADCgUIBQABNQAECgUIDQACAAAAAA==.Caldergrim:BAAANQADCgQIBAAAAA==.Calumen:BAAANQAECgUIBQAAAA==.Calypzo:BAAANQAECgMIAwAAAA==.Caserius:BAAANQADCggICAAAAA==.Casusbelli:BAAANQABCgIIAgAAAA==.Catta:BAAANQADCgMIBAABNQADCgYIBgACAAAAAA==.Catynca:BAAANQAECgEIAQABNQAECgUIDQACAAAAAA==.',
Ce='Celieril:BAAANQADCggIEgAAAA==.',
Ch='Changqing:BAAANQADCgUIBQABNQAECgUIBwACAAAAAA==.Chaparrín:BAAANQADCggICQAAAA==.Checoburger:BAAANQADCggIFAAAAA==.Cheiel:BAAANQAECgcIBwAAAA==.Chendruid:BAAANQADCgQIBAAAAA==.Chillheart:BAAANQADCgYIBgAAAA==.Chitoes:BAAANQADCgcIBwAAAA==.Chylan:BAAANQADCgUIBQAAAA==.',
Ci='Cincolobos:BAAANQAECgQIBAAAAA==.Cinnaminsaph:BAAANQAECgIIAgAAAA==.',
Cl='Cloraform:BAAANQADCgUIBgAAAA==.',
Co='Conduit:BAAANQAECgEIAQAAAA==.Conri:BAAANQADCggIEwAAAA==.Contremeo:BAAANQADCgQIBAAAAA==.Coradk:BAAANQADCggICAABNQAECgkJGQADAHcgAA==.Cowmooz:BAAANQAECgQIBAAAAA==.',
Cr='Critaurus:BAAANQAECgUIDgAAAA==.Cronics:BAAANQADCgUIBQABNQAECgQIBAACAAAAAA==.Cronstione:BAAANQAECgYIBwAAAA==.Crushinater:BAAANQAECgQIBwAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggICgAAAA==.',
Cz='Czrp:BAAANQADCgQIBAAAAA==.',
['Cô']='Côrack:BAABNQAECoEZAAIDAAkJdyCqBwBGAwADAAkJdyCqBwBGAwAAAA==.',
Da='Dad:BAAANQAECgcIBwAAAA==.Daddytank:BAAANQADCgUIBQAAAA==.Daeemon:BAAANQADCgcIBwABNQAECgYICgACAAAAAA==.Dagaa:BAAANQADCgYICwAAAA==.Dagdeath:BAAANQAECgQIBwAAAA==.Dagmarre:BAAANQADCgcIBwAAAA==.Dagothseth:BAAANQAECgEIAQAAAA==.Dagothsett:BAAANQADCgMIAwAAAA==.Daktz:BAAANQADCgYIBgAAAA==.Danelle:BAAANQADCgUICgAAAA==.Dankest:BAAANQADCgcIDwAAAA==.Darfòrce:BAAANQAECgIIAwABNQAFFAUIBwAEAPcaAA==.Darison:BAAANQAECgQIBgAAAA==.Darkobey:BAAANQADCgEIAQAAAA==.Darreck:BAAANQAECgcIEwAAAA==.Darthmommy:BAAANQADCgYICgAAAA==.Darvus:BAAANQADCgEIAQAAAA==.Darwïn:BAAANQAECgEIAQAAAA==.Datonax:BAAANQAECgYICwAAAA==.Davinity:BAAANQAECgQIBQAAAA==.Dayfire:BAAANQAECgIIAgAAAA==.',
Dd='Ddrizztt:BAAANQAECgMIAwAAAA==.',
De='Deadskill:BAAANQAECgYIEgAAAA==.Deathburrito:BAAANQADCgIIAgAAAA==.Deathloky:BAAANQAECgEIAQAAAA==.Decca:BAAANQAECgQIBwAAAA==.Deeroy:BAAANQAECgUIBwAAAA==.Dela:BAAANQAECgIIAgAAAA==.Delandèr:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Demincy:BAAANQAECgMIAwAAAA==.Demonbruff:BAAANQAECgUICAAAAA==.Demonflex:BAAANQAECgMIAwAAAA==.Deoxys:BAAANQADCggICgAAAA==.Deset:BAAANQAECgQIBAAAAA==.Desprainer:BAAANQADCgYICgAAAA==.Desse:BAAANQADCgQIBAAAAA==.Deydoria:BAAANQADCgIIAgAAAA==.',
Di='Dingùs:BAAANQAECgUIBQABNQAECgUICAACAAAAAA==.Dirkadeux:BAAANQAECgUICQAAAA==.Dirtyúndys:BAAANQAECgEIAQAAAA==.Discoliquid:BAAANQABCgEIAQAAAA==.Divinatrix:BAAANQADCgMIAwAAAA==.Divinecakes:BAAANQAECgQICAAAAA==.Divineskillz:BAAANQAECgEIAQAAAA==.',
Do='Docmanhattan:BAAANQAECgMIAwAAAA==.Doesnttank:BAAANQADCgQICAAAAA==.Dogmatrix:BAAANQAECgYIDAAAAA==.Doomshock:BAAANQADCgEIAQAAAA==.Dotcom:BAAANQAECgEIAQAAAA==.Doughmaker:BAAANQAECgcIEgAAAA==.',
Dr='Dragonskillz:BAAANQADCgUIBQAAAA==.Dreamdekoop:BAAANQAFFAEIAQAAAA==.Drededknight:BAAANQADCgcIBwAAAA==.Dreignos:BAAANQAECgUICQAAAA==.Drizztski:BAAANQADCgUIBgABNQAECgMIAwACAAAAAA==.Drocalla:BAAANQAECgEIAQAAAA==.Drozghul:BAAANQADCgUICQAAAA==.',
Du='Durnhelm:BAAANQADCgYIBgABNQAECgYIDAACAAAAAA==.Dushawee:BAAANQAFFAEIAQAAAA==.',
['Dä']='Dävös:BAAANQAECgIIAgAAAA==.',
Ea='Earthwitch:BAAANQADCgcIDQABNQAECgYIEQACAAAAAA==.',
Eg='Egg:BAAANQAECggIDgABNQAECgkJFQAFAJ8kAA==.',
Ek='Ekalbs:BAAANQAECgUIBgAAAA==.',
El='Eliniia:BAAANQADCgUIBQAAAA==.Ellayri:BAAANQAECgYICgAAAA==.Elldis:BAAANQAECgMIBAAAAA==.Elleanor:BAAANQAECgMIBgAAAA==.Eltanin:BAAANQADCggIFAAAAA==.',
En='Endoblades:BAAANQADCgYICQABNQAECgUICAACAAAAAA==.Endocrits:BAAANQADCggIDgABNQAECgUICAACAAAAAA==.Endodaddy:BAAANQAECgIIAgABNQAECgUICAACAAAAAA==.Endostars:BAAANQAECgUICAAAAA==.Energykyouka:BAAANQAECgQIBQABNQAECgQIBQACAAAAAA==.Enferi:BAAANQAECgUICAAAAA==.Enforcers:BAAANQADCggIDgAAAA==.',
Eq='Equinoxdk:BAAANQAECgcICwAAAA==.',
Es='Essent:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.Esthera:BAAANQADCgYIBgAAAA==.',
Ev='Evochiken:BAEBNQAECoEYAAMGAAkJoBMnCQBtAgAGAAkJoBMnCQBtAgAHAAQJcws1FwDoAAAAAA==.Evokemode:BAAANQAECgcIDAAAAA==.',
Ex='Exorcism:BAAANQAECgIIAgAAAA==.Exotic:BAAANQAECgcIDAAAAA==.Explosivoh:BAAANQAECgIIAgAAAA==.Exumm:BAAANQAECgQIBAAAAA==.',
Ey='Eyeforagge:BAAANQADCgMIAwAAAA==.',
Fa='Fakelashes:BAAANQABCgQIBAAAAA==.Farstriderr:BAAANQADCgYIHAAAAA==.Fataleclipse:BAAANQAECgQIBgAAAA==.Fatmir:BAAANQADCgcIEAAAAA==.',
Fe='Feku:BAAANQADCgMIAwAAAA==.Feldrak:BAAANQAECggIDgAAAA==.Feldriu:BAAANQADCgYICQAAAA==.',
Fi='Figai:BAAANQAECgMIAwAAAA==.Finebyme:BAAANQAECgEIAQAAAA==.Firebear:BAAANQAECgUICQAAAA==.',
Fl='Flanknspank:BAABNQAECoEYAAIIAAkJHSBXAQB4AwAIAAkJHSBXAQB4AwAAAA==.',
Fo='Formulated:BAAANQABCgIIAgAAAA==.Fotmreroller:BAAANQAECgQIBAAAAA==.Fourtwenty:BAAANQAECgcIEgAAAA==.Foxylady:BAAANQABCgMIBAAAAA==.',
Fr='Frostytongue:BAAANQADCgUIBgAAAA==.Frôstíe:BAAANQAECgEIAQAAAA==.',
Ga='Galadriella:BAAANQAECgEIAQAAAA==.Garglius:BAAANQAECggIAwAAAA==.',
Ge='Gekidos:BAAANQADCgQIAwAAAA==.Gekiretsu:BAAANQAECgEIAQAAAA==.Geodon:BAAANQADCggIEgAAAA==.Geoffry:BAAANQAECgUIBgAAAA==.Gerbil:BAAANQAECgUIBwAAAA==.',
Gh='Ghostmonkey:BAAANQADCgEIAQAAAA==.',
Gi='Giaoman:BAAANQAECgcIDQAAAA==.Gilgalock:BAAANQADCgIIAgABNQAECgcIDAACAAAAAA==.Gilwood:BAAANQAECgcIEgAAAA==.Gingyr:BAAANQAECgUIBgAAAA==.Girthywand:BAAANQAECgQIBgAAAA==.',
Gl='Glacialgimp:BAAANQAECgMIAwAAAA==.Gloinn:BAAANQAECgcIEgAAAA==.',
Gn='Gnomelyfans:BAAANQAECgYICgAAAA==.',
Go='Golfire:BAABNQAECoEcAAMJAAkJ7x+xBQA0AwAJAAkJVR6xBQA0AwAKAAUJ/xszEwDJAQAAAA==.Gooberlol:BAAANQAECgcIBwAAAA==.Gorbashe:BAAANQADCgEIAQABNQAECgUIDgACAAAAAA==.Gorbie:BAABNQAECoEXAAIJAAkJCBcHDQCfAgAJAAkJCBcHDQCfAgAAAA==.Gorestus:BAAANQAECgUIBgAAAA==.Gorlockholms:BAAANQAECgUIBgAAAA==.Gorthex:BAAANQAECgQIBAAAAA==.Gozziz:BAAANQADCggIEwAAAA==.',
Gr='Graitlok:BAAANQAECgUICAAAAA==.Grawd:BAAANQAECgQIBQAAAA==.Graysòn:BAAANQAECgMIAwAAAA==.Grilledchis:BAAANQAECgcIDQAAAA==.Grimdwagon:BAAANQADCgcIDQAAAA==.Griplaka:BAAANQAECggIBgABNQAECggIBwACAAAAAA==.Griswald:BAAANQAECgEIAQABNQAECgQIBAACAAAAAA==.Grumpygranpa:BAAANQAECgIIAwAAAA==.Grypser:BAAANQADCgQIBAAAAA==.',
Gu='Guesswholoky:BAAANQADCgYICgAAAA==.Guldán:BAAANQADCgUIBQAAAA==.Gulmatt:BAAANQAECgQIBwAAAA==.Gunslug:BAAANQADCgIIAgAAAA==.',
['Gí']='Gílgamore:BAAANQAECgcIDAAAAA==.',
Ha='Haguda:BAAANQADCggIDgAAAA==.Hakaska:BAAANQAECgUICQAAAA==.Hakkinen:BAAANQAECgEIAQAAAA==.Hanswolo:BAAANQADCggIEAAAAA==.Haramboned:BAAANQADCggIDgAAAA==.Harharof:BAAANQADCgIIAgAAAA==.Hatebreeder:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Hatise:BAAANQADCgQIBAAAAA==.Hawktuàh:BAAANQADCgUIBgAAAA==.',
He='Heliotoro:BAAANQADCgUIBQAAAA==.',
Hi='Hierba:BAAANQADCggICAAAAA==.Highlock:BAAANQADCggICQAAAA==.',
Ho='Holigoat:BAAANQADCgIIAgAAAA==.Holyshhmon:BAAANQAECgEIAQAAAA==.Holystriker:BAAANQADCgUIBgAAAA==.Holywitch:BAAANQAECgYIEQAAAA==.Honnycorns:BAAANQAECgYICQAAAA==.Hoojah:BAAANQADCgIIAgAAAA==.Hormandacek:BAAANQADCgcIDQAAAA==.Hornguy:BAAANQAECgEIAQAAAA==.Houndoom:BAAANQAECggIDAAAAA==.',
Hr='Hrulot:BAAANQADCgYIBgAAAA==.',
Hs='Hsr:BAAANQAECgcIDQAAAA==.',
Hu='Huataurga:BAAANQAECgUICgAAAA==.Huff:BAAANQAECgUICgABNQAFFAIIAgACAAAAAA==.Huktwo:BAAANQAECgIIAgAAAA==.Hunternin:BAAANQAECgIIAgAAAA==.Huron:BAAANQAECgQIBAAAAA==.Hussypriest:BAAANQAECgEIAQAAAA==.',
Hy='Hyzerflip:BAAANQADCggICwAAAA==.',
['Hà']='Hàchi:BAABNQAECoEXAAILAAkJqSNyAwCGAwALAAkJqSNyAwCGAwAAAA==.',
Ib='Ibsgodx:BAAANQADCgQIBAAAAA==.',
Id='Idiotfurry:BAAANQAECgUICQAAAA==.',
Ig='Igotatiara:BAAANQADCgYICQAAAA==.',
Il='Ilmagnifico:BAAANQAECgcIDgAAAA==.',
Im='Imolegreg:BAAANQAECgYIBwAAAA==.Imperatris:BAAANQAECgEIAQAAAA==.Imvaernarhro:BAAANQADCgMIAwAAAA==.',
In='Inkubator:BAAANQAFFAEIAQAAAQ==.Inkyy:BAAANQADCgYIBgAAAA==.',
Ir='Irøns:BAAANQADCgYIDQAAAA==.',
It='Itemlevel:BAAANQADCgUIBgAAAA==.',
Iy='Iyamwarlock:BAAANQADCgYIBgAAAA==.Iyanden:BAAANQADCggIFAAAAA==.',
Ja='Jabrogoz:BAAANQADCgMIAQAAAA==.Jalahl:BAAANQADCgcIBwABNQAECgkJFgAMACoiAA==.Jastinos:BAAANQAECgQIBAAAAA==.',
Je='Jentrazka:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Jezahbel:BAAANQAECgMIAwAAAA==.',
Ji='Jitteryjoe:BAAANQAECgQIBQAAAA==.',
Jo='Jokich:BAAANQABCgYICAAAAA==.Joseko:BAAANQAECgUIBgAAAA==.',
Ju='Juggsr:BAAANQAECgQIBgAAAA==.Justbower:BAAANQADCgEIAQAAAA==.',
Ka='Kaeyle:BAAANQADCgcIDgABNQAECgkJFwANANccAA==.Kamico:BAAANQADCgUICQAAAA==.Kansoika:BAAANQADCgcIBwAAAA==.Karakitana:BAAANQADCgYIBQABNQAECgYICgACAAAAAA==.Kasualtrash:BAAANQADCgMIAwAAAA==.Katfury:BAAANQAECgUICQAAAA==.Kattallina:BAAANQADCgcIBwAAAA==.Kattmini:BAABNQAECoEYAAMFAAkJvh54CwC5AgAFAAgJSx14CwC5AgAOAAcJ/BTLDQDmAQAAAA==.Katto:BAAANQADCgYIBgAAAA==.',
Ke='Keffká:BAAANQADCgIIAgAAAA==.Keyalidas:BAAANQADCgEIAQAAAA==.Keylime:BAAANQADCggICAAAAA==.',
Kh='Khane:BAAANQADCggIDQAAAA==.Kharras:BAAANQADCggICgAAAA==.',
Ki='Killabattle:BAAANQADCgcIBwAAAA==.Kilyna:BAAANQAECgUICgAAAA==.Kirbÿ:BAAANQAECgEIAQAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECgkJGQADAJ8WAA==.Kodita:BAABNQAECoEZAAIDAAkJnxa6EgC3AgADAAkJnxa6EgC3AgAAAA==.',
Kr='Krakair:BAAANQAECgEIAQAAAA==.Krhon:BAAANQAECgQIBwAAAA==.Kryptic:BAAANQAECgMIAwAAAA==.',
Ky='Kylea:BAAANQAECgEIAQAAAA==.Kyntaro:BAAANQADCgcICQAAAA==.Kyouka:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.Kysira:BAAANQAECgQIBQAAAA==.',
La='Lailai:BAAANQAECgUICAAAAA==.Lalax:BAAANQABCgQIBAAAAA==.Lalechuga:BAAANQAECgQIBQAAAA==.Lanerian:BAAANQADCggIGQAAAA==.',
Ld='Ldytncty:BAAANQADCgUIBQAAAA==.',
Le='Leadah:BAAANQADCgUIBQAAAA==.Ledge:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Ledgebear:BAAANQAECgIIAgAAAA==.Leerwandler:BAAANQAECgQIBAAAAA==.Lehunt:BAAANQAECgcIDgAAAA==.Letmedoitpls:BAAANQABCgMIBQAAAA==.Levigosa:BAAANQADCgYIDAAAAA==.Lexadin:BAAANQABCgIIAgAAAA==.Leylanie:BAAANQAECgQIBgAAAA==.',
Li='Liadarel:BAAANQADCgMIAwAAAA==.Liael:BAAANQADCgQIBAAAAA==.Lightlobster:BAAANQAECgQIBAABNQAECgkJFgANAJceAA==.Lilpuffz:BAAANQAECgQIBQAAAA==.Lisaleri:BAAANQADCgYIBwAAAA==.Liteorheavy:BAAANQADCgIIAgAAAA==.Livewires:BAAANQADCgcICQABNQAECgIIAgACAAAAAA==.',
Ll='Llandshark:BAAANQAECgQIBAAAAA==.Lleyla:BAAANQAECgUIDQAAAA==.',
Lo='Lockyboi:BAAANQADCgUIBQABNQAECgQIBAACAAAAAA==.Locomoko:BAAANQADCggICAAAAA==.Lojik:BAAANQADCgUIBQAAAA==.Long:BAAANQAECgQIBwAAAA==.Lookimapanda:BAAANQADCgcIBwAAAA==.Lorakmahktar:BAAANQADCggIFgAAAA==.Lottie:BAAANQADCggICAAAAA==.',
Lu='Luarhea:BAAANQAECgIIAgAAAA==.Luccina:BAAANQAECgQIBQAAAA==.Lucîd:BAAANQAECgQICAAAAA==.Luminarie:BAAANQAECgcIEgAAAA==.Lunitari:BAAANQAECgYIDAAAAA==.Luvalot:BAAANQAECgIIAwAAAA==.',
Lx='Lxbeowulfxl:BAAANQADCgcICgAAAA==.',
Ly='Lyraiel:BAAANQAECgYIDAAAAA==.',
['Lü']='Lücíd:BAAANQADCgQIBAABNQAECgQICAACAAAAAA==.',
Ma='Mackantosh:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.Mackpyre:BAAANQAECgMIAwAAAA==.Madness:BAAANQABCgYIBwAAAA==.Magmalash:BAAANQADCgEIAQAAAA==.Magoroxx:BAAANQAECgUIBQAAAA==.Mahots:BAAANQAECgMIAwAAAA==.Maiyathicc:BAAANQAECgMIAwAAAA==.Makagalvan:BAAANQAECgcIEgAAAA==.Malthael:BAABNQAECoEYAAIBAAkJ7iMeBQCUAwABAAkJ7iMeBQCUAwAAAA==.Malzahar:BAAANQADCgcIBwAAAA==.Manamgmtllc:BAAANQADCgYIBgAAAA==.Markyle:BAEANQADCgYIBgABNQAECgIIAgACAAAAAA==.Martien:BAAANQAECgEIAgAAAA==.Massteraria:BAAANQADCggIDwAAAA==.Masstercard:BAAANQAECgcIDAAAAA==.Maxeras:BAAANQADCggIDwAAAA==.Maximus:BAAANQAECgQIBQAAAA==.Maya:BAAANQAECgUICQAAAA==.Mazo:BAAANQAECgcIDgAAAA==.',
Mb='Mbuku:BAAANQADCgUIBQAAAA==.',
Mc='Mcroguez:BAAANQAECgcIDQAAAA==.',
Me='Meeche:BAAANQAECgQIBAAAAA==.Menagerie:BAAANQAECgYICwAAAA==.Metche:BAAANQADCgYIBgAAAA==.',
Mi='Mightythighs:BAAANQAECgUICAAAAA==.Mihd:BAAANQAECgMIAwAAAA==.Miisch:BAAANQAECgQIBgAAAA==.Milkyy:BAAANQAECgYIDgAAAA==.Millamaxwell:BAAANQADCgcICwABNQAECgcIEgACAAAAAA==.Minimus:BAAANQAECgQIBQAAAA==.Miraeth:BAAANQAECgEIAQAAAA==.Misknocker:BAAANQAECgMIAwAAAA==.',
Mo='Moistivall:BAAANQADCgUIBgAAAA==.Moisturize:BAAANQABCgMIAwAAAA==.Momô:BAAANQAECgIIAwAAAA==.Monkred:BAAANQADCggICAAAAA==.Monte:BAAANQADCggIEAAAAA==.Moobees:BAAANQAECgQIBQAAAA==.Mooge:BAEANQADCgYICwABNQAECgIIAgACAAAAAA==.Moomanchuu:BAAANQADCgMIAwAAAA==.Moomins:BAAANQADCgcIBwABNQAECgYIDAACAAAAAA==.Mortuous:BAAANQAECgEIAQAAAA==.',
Ms='Mstrfreekill:BAAANQAECgYICQAAAA==.',
Mu='Mubu:BAAANQAECgEIAQAAAA==.Mudpriest:BAAANQAECgUICQAAAA==.Muffdiiva:BAAANQAECgMIAwAAAA==.Mulletman:BAAANQAECgQICQAAAA==.Musky:BAAANQAECgYICgAAAA==.Muskydk:BAAANQADCgYIBgAAAA==.Muskydruid:BAAANQADCgcIBwAAAA==.Muskyshnoze:BAAANQADCgQIBQAAAA==.',
My='Mystogån:BAAANQADCggIDwAAAA==.Mystrix:BAAANQAECgMIAwAAAA==.Mytthdk:BAAANQADCgcIBwAAAA==.Myzary:BAAANQADCggIDQAAAA==.',
['Mè']='Mèggz:BAAANQADCgIIAwAAAA==.',
['Më']='Mërcy:BAAANQAECgEIAQAAAA==.',
['Mí']='Míthrandír:BAABNQAECoEXAAIPAAgJEh+1HQDlAgAPAAgJEh+1HQDlAgAAAA==.',
['Mô']='Mômo:BAAANQAECgEIAQABNQAECgIIAwACAAAAAA==.',
['Mû']='Mûfâsâ:BAAANQADCggIDgAAAA==.',
Na='Nardhaa:BAAANQAECgUICAAAAQ==.Narkiel:BAAANQADCgEIAQAAAA==.Narrius:BAAANQAECgMIAwAAAA==.Natraps:BAAANQAECgIIAgAAAA==.',
Ne='Neartonoir:BAAANQABCgYIBwAAAA==.Nesmie:BAAANQAECgYICQAAAA==.',
Ni='Nijek:BAAANQAECgUIBQAAAA==.Nimchip:BAABNQAECoElAAIBAAgJeR8vGgCzAgABAAgJeR8vGgCzAgAAAA==.',
Nl='Nlrvana:BAAANQADCgEIAQAAAA==.',
No='Nokkakkash:BAAANQADCggICAAAAA==.Notmyforte:BAAANQAECgIIAgAAAA==.',
Nu='Nudillos:BAAANQADCgcIBwAAAA==.Nudnarb:BAAANQADCgQIBAAAAA==.',
Ny='Nyankobrq:BAAANQAECgQIBQAAAA==.Nyxtheabyss:BAAANQADCgQIBAAAAA==.',
['Ná']='Náthe:BAAANQADCgYICgAAAA==.',
Oa='Oakzz:BAAANQAECgYIBgAAAA==.',
Ob='Obalnhabdea:BAAANQADCggIFAAAAA==.Oblvn:BAAANQADCgcIEAAAAA==.',
Oc='Ocêangrown:BAAANQADCggIBQAAAA==.',
Od='Odhran:BAAANQADCggIDgAAAA==.',
Oh='Ohda:BAAANQAECgEIAQAAAA==.Ohgodbees:BAAANQAECgEIAgAAAA==.',
On='Onepiece:BAAANQADCgQIBQAAAA==.Onís:BAAANQAECgQIBgAAAA==.',
Op='Opspartan:BAAANQABCgQIBwAAAA==.',
Or='Orastal:BAAANQADCgUIBgABNQAECgQIBwACAAAAAA==.Oravoker:BAAANQAECgQIBwAAAA==.Orcishz:BAAANQADCgQIBwAAAA==.Oreweyna:BAAANQABCgIIBAAAAA==.Orion:BAAANQADCgcIDAAAAA==.',
Os='Osawa:BAAANQADCgYIBgABNQAECgQIBgACAAAAAA==.Ostidevache:BAAANQADCgYICQAAAA==.',
Oy='Oyobi:BAAANQADCgEIAQAAAA==.',
Oz='Ozshock:BAAANQAECgUIBgAAAA==.',
Pa='Paffdk:BAAANQAECgUIDQAAAA==.Paiyn:BAAANQADCgcIBwAAAA==.Palamix:BAAANQADCgIIBAABNQAECgIIAgACAAAAAA==.Palladone:BAAANQAECgMIAwAAAA==.Palthron:BAAANQAECgMIBAAAAA==.Palychick:BAAANQAECgIIAgAAAA==.Pampersxl:BAAANQAECgUICQAAAA==.Pandatheis:BAAANQADCgUIBQAAAA==.Pandatotem:BAAANQADCgYIBgAAAA==.Pangoro:BAABNQAECoEYAAIJAAkJIx4TBgAsAwAJAAkJIx4TBgAsAwAAAA==.Paragondk:BAAANQAECgYICgAAAA==.Paragonlock:BAAANQAECgEIAQABNQAECgYICgACAAAAAA==.Paramedic:BAAANQADCgIIAgABNQAECgkJGAABAO4jAA==.Parser:BAAANQADCgMIAwAAAA==.',
Pe='Pelikanesis:BAAANQAECgEIAQAAAA==.Pelolindo:BAAANQADCggICAAAAA==.Penance:BAAANQAECgMIBAAAAA==.Pestus:BAAANQADCgUICQAAAA==.Peteqc:BAAANQADCgUIBQAAAA==.Petshunt:BAAANQADCggIGAABNQADCggICQACAAAAAA==.',
Ph='Phageborn:BAABNQAECoEVAAIQAAgJxSN2BQA8AwAQAAgJxSN2BQA8AwAAAA==.Phiavel:BAAANQADCgYIDAAAAA==.Philmahuders:BAAANQADCgIIAgAAAA==.Phoop:BAAANQADCgYIDQAAAA==.',
Pi='Pik:BAAANQAECgMIAwAAAA==.Pillowpants:BAAANQAECgQIBgAAAA==.Pineappleish:BAAANQAECgMIAwAAAA==.Pinkcross:BAAANQAECgIIAwABNQAFFAUIAQACAAAAAA==.Pinkfuzi:BAAANQADCgcIEgAAAA==.',
Po='Pocketlockit:BAAANQADCgUIBQABNQAECgYIBwACAAAAAA==.Poisonousx:BAAANQADCgYICgAAAA==.Poka:BAAANQAECgIIAgAAAA==.Poluna:BAAANQAECgIIAgAAAA==.Popsiclegirl:BAAANQADCgQIBAAAAA==.Porkkchopp:BAAANQAECgYICgAAAA==.',
Pr='Prayermonger:BAAANQAECgcIEgAAAQ==.Protendo:BAAANQADCggICAAAAA==.Provider:BAAANQAECgEIAQAAAA==.',
Pu='Pufftreez:BAAANQAECgUICQAAAA==.Purplatath:BAAANQADCgYICAAAAA==.Purpledrink:BAAANQAECgQIBgAAAA==.Purplette:BAAANQADCggICwAAAA==.Purplizor:BAAANQAECgIIAgAAAA==.',
Pw='Pwincessmeow:BAAANQADCgYIEQAAAA==.',
Py='Pynki:BAAANQADCggICwAAAA==.Pyroxion:BAAANQADCgQIBgAAAA==.Pyrìz:BAAANQAECgIIBAAAAA==.',
Qi='Qiill:BAAANQADCgYIBgAAAA==.',
Qu='Quadratic:BAAANQADCgUIBwAAAA==.Quikzmagez:BAAANQADCgYIBgAAAA==.Quikzpriest:BAAANQADCgYIBQAAAA==.',
Qw='Qweefur:BAAANQADCgYIBgAAAA==.',
Ra='Rabidwombat:BAAANQAFFAIIAgAAAA==.Racoto:BAAANQAECgIIAgAAAA==.Ragingwagyu:BAAANQADCgYIBgAAAA==.Ragrega:BAAANQADCgIIAgABNQAECgUICAACAAAAAA==.Rainey:BAAANQADCgIIAgAAAA==.Ralokian:BAABNQAECoEWAAMMAAkJKiLfAQChAgAMAAcJ1iLfAQChAgAHAAcJKB6NCABVAgAAAA==.Rangoo:BAAANQADCgUIBQAAAA==.Raphaelle:BAAANQAECgQIBQAAAA==.Ravelled:BAAANQAECgEIAQAAAA==.Ravencláw:BAAANQADCgUIBQAAAA==.Ravenmane:BAAANQAECgcICQAAAA==.Rawdaug:BAAANQAECgQIBAAAAA==.Razziz:BAAANQAECgIIAgAAAA==.Raín:BAAANQADCgYIDAAAAA==.',
Re='Regolas:BAAANQADCggIFAAAAA==.Rejuvie:BAAANQAECgcIDwAAAA==.Relzzad:BAAANQAECgMIAwAAAA==.Renalyne:BAAANQADCgEIAQABNQAECgkJFwARAAAcAA==.Rentámonk:BAAANQADCgEIAQABNQAECgQIBAACAAAAAA==.Rentápally:BAAANQAECgQIBAAAAA==.Revelätion:BAAANQADCgYIDAAAAA==.Rexxaar:BAAANQAECgIIAgAAAA==.',
Ri='Riata:BAAANQAECgQIBwAAAA==.Ricericebaby:BAAANQAECgEIAQAAAA==.Rikaya:BAAANQAECgEIAQAAAA==.',
Ro='Robertcheeto:BAAANQAECgcIEgAAAA==.Rogchamita:BAAANQAECgYICAAAAA==.Ronalde:BAAANQAECgEIAQAAAA==.Rondall:BAAANQAECgQIBAAAAA==.Rousera:BAAANQAECgYICgAAAA==.Roxxaan:BAAANQADCgcIEAAAAA==.Royvn:BAAANQAECgQIBQAAAA==.',
Ru='Ruffels:BAAANQAECgEIAQAAAA==.Runtzz:BAAANQADCgMIAwAAAA==.',
Ry='Ryushinizi:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.',
Sa='Saberana:BAAANQADCgYICQAAAA==.Sadllama:BAAANQAECgQIBgAAAA==.Saintcow:BAAANQADCgYIBgAAAA==.Saintl:BAAANQAECgcIEgAAAA==.Sammwow:BAAANQAECgUICQAAAA==.Sammyl:BAAANQABCgQIBgAAAA==.Sanalin:BAAANQADCgIIAgAAAA==.Sanlerøs:BAAANQAECgEIAQAAAA==.Saranfarmer:BAAANQAECgYIDAAAAA==.Sarantakos:BAAANQADCgYICgABNQAECgYIDAACAAAAAA==.Sarviez:BAAANQADCgcIBwAAAA==.Sass:BAAANQADCggICAABNQAECgUICAACAAAAAA==.',
Sc='Schwetyß:BAAANQABCgYICgAAAA==.Scolio:BAAANQADCggIDgAAAA==.Scourgeguy:BAAANQAECgIIAwAAAA==.',
Se='Separation:BAAANQADCgUIBgAAAA==.Seves:BAAANQADCgcIDAAAAA==.',
Sh='Shadosham:BAAANQADCggIFQAAAA==.Shadowcakes:BAAANQADCgYIBgAAAA==.Shadowsmith:BAAANQAECgcIEgAAAA==.Shamooky:BAEANQAECgIIAgAAAA==.Shanke:BAAANQAECgIIAgAAAA==.Shieldbane:BAAANQADCggICAAAAA==.Shizzkin:BAAANQADCgcIBwAAAA==.Shmotz:BAAANQABCgIIAgAAAA==.Shocktoke:BAAANQAECgEIAQAAAA==.Shockzone:BAAANQADCggIEwAAAA==.Shootymcgun:BAAANQAECgIIAgAAAA==.Shots:BAAANQAECgcIEgAAAA==.Shotsonshots:BAAANQADCggIDQAAAA==.Shoulders:BAAANQAECgUIBQAAAA==.',
Si='Siado:BAAANQAECgEIAQAAAA==.Sidesandwich:BAAANQAECgEIAQAAAA==.Sinthetic:BAAANQADCggIJwAAAA==.Siqi:BAAANQADCgEIAQAAAA==.',
Sk='Skornn:BAAANQADCgIIAgAAAA==.Skyfangret:BAAANQADCgYICgAAAA==.Skysweep:BAAANQADCgYICAABNQAECgQIBQACAAAAAA==.',
Sl='Slag:BAAANQADCgcIEAABNQADCgYIBgACAAAAAA==.Slayerlilith:BAAANQADCgIIAgAAAA==.Slickxoxo:BAAANQADCgcIBwAAAA==.Slizaro:BAAANQAECgYICgAAAA==.Sloponmyknob:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
Sm='Smashendash:BAAANQAECgMIAwAAAA==.Smolslaps:BAAANQAECgYIBwABNQADCgYIBgACAAAAAA==.',
Sn='Snakeyess:BAAANQADCggICgAAAA==.Snappypuppy:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.',
So='Sockemm:BAAANQAECgUIBQAAAA==.Sollaria:BAAANQABCgYICQAAAA==.Sorchanna:BAAANQADCgcICAAAAA==.Soulamander:BAAANQAFFAMIAwAAAA==.Souza:BAAANQAECgMIBQAAAA==.Soül:BAAANQAECggIDwAAAA==.',
Sp='Spikeyboy:BAAANQADCgYIBgAAAA==.Spinal:BAAANQAECgQIBAAAAA==.Spiritfinger:BAAANQAECgUIBQABNQAECgcICQACAAAAAA==.',
Sq='Sqrood:BAAANQAECgQICAAAAA==.Squâll:BAAANQAECgEIAQAAAA==.',
Sr='Srdlosrayoz:BAAANQAECggICAAAAA==.',
St='Stativa:BAAANQADCgYIBgAAAA==.Stellaris:BAAANQAECgUIBwAAAA==.Stevesmiff:BAAANQADCgQIBgAAAA==.Sting:BAAANQAECgMIAwAAAA==.Stoofy:BAAANQADCgQIBAABNQAECgkJGAAIAB0gAA==.Stormbreakur:BAAANQADCggIDAAAAA==.Stormskillz:BAAANQADCgYIBgAAAA==.',
Su='Sugarhammer:BAAANQADCgEIAQAAAA==.Sunarri:BAAANQADCgYIDAAAAA==.Sunbourne:BAAANQAECgQIBQAAAA==.Suradin:BAAANQAECgUIBgAAAA==.Surín:BAAANQADCgcIBwAAAA==.',
Sy='Syrathia:BAAANQAECgIIAwAAAA==.',
['Sî']='Sîcarius:BAAANQADCgcIDgAAAA==.',
['Sú']='Súrë:BAABNQAECoEZAAIGAAkJsx/6AgAxAwAGAAkJsx/6AgAxAwAAAA==.',
Ta='Tahtics:BAAANQAECgYIBgAAAA==.Talmahua:BAAANQADCgUIBQAAAA==.Tangolay:BAAANQADCgIIAgABNQAECgMIBAACAAAAAA==.Tatyl:BAAANQAECgcIEAAAAA==.Tazana:BAAANQADCgYICwAAAA==.',
Te='Tehsirus:BAAANQAECgQIBQAAAA==.Temoro:BAAANQADCgYIBgABNQADCggICAACAAAAAA==.Tempestaurus:BAAANQAECgcICwAAAA==.Tenkok:BAAANQAECgMIAwAAAA==.Tewpok:BAABNQAECoEWAAQSAAcJPwydBABpAQASAAYJQwudBABpAQAOAAIJ3QxoPAB7AAAFAAEJgAo9jQA3AAAAAA==.',
Th='Thalisan:BAAANQAECgIIAgAAAA==.Thatmage:BAAANQAECgMIAwAAAA==.Theirashes:BAAANQADCgMIAwABNQAECgkJGAATALMhAA==.Themoistest:BAAANQAECgMIAwAAAA==.Theothehero:BAAANQAECgYIDgAAAA==.Thirdhank:BAAANQADCgYIBgAAAA==.Thoar:BAABNQAECoEXAAINAAkJ1xwrAgAgAwANAAkJ1xwrAgAgAwAAAA==.Thormoon:BAAANQAECgUICQAAAA==.',
Ti='Tiahdoe:BAAANQADCggIDgAAAA==.Tiariel:BAAANQADCggIEAAAAA==.Tiriq:BAAANQADCgcIEAAAAA==.',
To='Tolnar:BAAANQAECgYICwAAAA==.Tolnter:BAAANQADCgYIDAAAAA==.Tompo:BAEANQAECgYIAwAAAA==.Toodle:BAAANQAECgYICAAAAA==.Torgrun:BAAANQAECgIIAgAAAA==.Torniak:BAAANQAECgEIAQAAAA==.Torpor:BAAANQADCggIDQAAAA==.',
Tr='Traplock:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Trapple:BAAANQADCgYIBgABNQAECgQICAACAAAAAA==.Trillian:BAAANQADCggICAAAAA==.Trixia:BAAANQAECgYICwAAAA==.Troudeseve:BAAANQADCgcIDQAAAA==.',
Tu='Tusenpai:BAAANQAECgEIAQAAAA==.',
Tw='Twiggyy:BAAANQAECgQIBgAAAA==.',
Ty='Tyburr:BAAANQAECggIBgAAAA==.',
Tz='Tzye:BAAANQADCgEIAQAAAA==.',
['Tâ']='Tângo:BAAANQAECgMIBAAAAA==.',
Uj='Ujellypalz:BAAANQAECgEIAQAAAA==.Ujio:BAAANQADCgYIBgABNQAECgYIDQACAAAAAA==.',
Um='Umbráe:BAAANQAECgcIEgAAAA==.Umoonar:BAAANQADCgYIBgAAAA==.',
Un='Unctekay:BAAANQABCgIIAgAAAA==.',
Ur='Ursainsanis:BAAANQAECgIIAgAAAA==.',
Va='Vainless:BAAANQADCgIIAgAAAA==.Valhalla:BAAANQAECgIIAgAAAA==.Vallynn:BAAANQADCgQIBAAAAA==.Vandle:BAAANQAECgUIDQAAAA==.Vanoranda:BAAANQADCgIIAgABNQAECgUIBQACAAAAAA==.Variena:BAAANQADCgcIBgAAAA==.Varikk:BAAANQADCgYIDAAAAA==.Varmage:BAAANQADCgYIBgAAAA==.Varmmy:BAAANQADCgYIBgABNQADCggICAACAAAAAA==.Varrair:BAAANQADCggICAAAAA==.Vashezzo:BAAANQAFFAIIAgABNQAFFAUICQAUAGsYAA==.',
Ve='Velein:BAAANQADCgYICQAAAA==.Vellyssa:BAAANQAECgQIBQAAAA==.Verdolaga:BAAANQADCgYIBgAAAA==.Vexys:BAAANQADCgUIBQAAAA==.Veyllor:BAAANQAECgQIBQAAAA==.',
Vi='Villainous:BAAANQAECgQIBAAAAA==.Vindorian:BAAANQADCggICAAAAA==.Vitreshilla:BAAANQADCggICAABNQAECgQIBQACAAAAAA==.Vixenz:BAAANQAECgIIAgAAAA==.',
Vo='Volteer:BAAANQAECgcIEgAAAA==.Voxian:BAAANQADCgYIBgAAAA==.',
Vr='Vriest:BAAANQADCggICAAAAA==.',
Vy='Vyecodin:BAAANQADCgYIBgAAAA==.Vyr:BAEBNQAECoEZAAIVAAkJbBvTBQAXAwAVAAkJbBvTBQAXAwAAAA==.',
['Vä']='Väryn:BAAANQAECgMIAwAAAA==.',
Wa='Wannabrownie:BAAANQADCgUIAwAAAA==.Wardrian:BAAANQAECgEIAQAAAA==.Warriorzors:BAAANQABCgQIBAAAAA==.Wavyfist:BAAANQADCgQIBAABNQAECgcIEwACAAAAAA==.Way:BAAANQAECgEIAQAAAA==.',
We='Wellith:BAAANQAECgcIDAAAAA==.Westìn:BAAANQADCgEIAQAAAA==.',
Wi='Wikdtwstr:BAAANQAECgQIBwAAAA==.Wildcard:BAAANQAECgQIAwAAAA==.Wilder:BAAANQAECgQIBQAAAA==.',
Wo='Wolfir:BAAANQADCggIEAAAAA==.',
Wt='Wtfchickenz:BAAANQAECgIIAgABNQAECgQIBgACAAAAAA==.',
Wu='Wuntch:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.',
['Wã']='Wãngs:BAAANQAECgQIBAAAAA==.',
Xa='Xaev:BAAANQAECgIIAgAAAA==.Xandekay:BAAANQAECgEIAQABNQAECgcICwACAAAAAA==.Xarathiel:BAAANQADCgUIBQAAAA==.',
Xe='Xecution:BAAANQAECgUICAAAAA==.Xenthor:BAAANQADCgUIBQAAAA==.Xeseparg:BAEANQADCgYIBgABNQAECggIAQACAAAAAA==.Xevorian:BAAANQAECgIIAgAAAA==.',
Xi='Xiexieping:BAAANQAFFAIIAgAAAA==.',
Xy='Xyris:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.',
Ye='Yedranna:BAAANQADCgIIAgAAAA==.',
Yo='Yoloswagcrew:BAAANQAECgYICgAAAA==.Yooksham:BAAANQAFFAIIAgAAAA==.',
Ys='Yslena:BAAANQABCgYICAAAAA==.',
Yu='Yuebing:BAAANQAECgcIEgAAAA==.Yumin:BAAANQADCgUIBQAAAA==.Yurmagesty:BAAANQAECgMIAwAAAA==.',
['Yà']='Yàkana:BAAANQADCgQIBwAAAA==.',
Za='Zaeta:BAAANQAECgMIAwAAAA==.Zaetini:BAAANQADCgQIBQABNQAECgMIAwACAAAAAA==.Zamforia:BAAANQAECgUIBgAAAA==.Zandadead:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Zarellia:BAAANQAECgMIAwAAAA==.',
Ze='Zeeleez:BAAANQABCgIIAgAAAA==.Zephyrr:BAAANQADCggIDgABNQAECgIIAgACAAAAAA==.Zerathrot:BAAANQADCgMIAwAAAA==.Zevaran:BAAANQADCgIIAgABNQAECgkJFwAWAJkjAA==.Zexeria:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.',
Zi='Zingara:BAAANQADCgEIAQAAAA==.',
Zo='Zootz:BAAANQADCgYICAAAAA==.Zorrghen:BAAANQADCgYICwABNQAECgYICgACAAAAAA==.Zounap:BAAANQAECgIIAwAAAA==.Zoyaa:BAAANQADCggIDgAAAA==.',
Zu='Zultra:BAAANQADCgcICAAAAA==.',
['Zë']='Zëd:BAAANQADCgIIAgAAAA==.',
['Ïs']='Ïshtãr:BAAANQAECgMIAwAAAA==.',
['Üt']='Üthér:BAAANQAECgQIBQAAAA==.',
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
