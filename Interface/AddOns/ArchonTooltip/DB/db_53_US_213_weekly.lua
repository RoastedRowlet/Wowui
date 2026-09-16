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

local lookup = {'Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Rogue-Assassination','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Holy','Evoker-Preservation','Rogue-Outlaw','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Unknown-Unknown','Paladin-Protection','Mage-Arcane','Druid-Balance','Shaman-Enhancement','DeathKnight-Unholy','Monk-Mistweaver','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','Mage-Frost','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Havoc','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Fury',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aarg:BAAANQAECggICAAAAA==.',
Ac='Achillguy:BAAANQADCgUIBQAAAA==.',
Ag='Agnostic:BAABNQAECoEbAAIBAAkJaR0DEAD4AgABAAkJaR0DEAD4AgAAAA==.Agonybehold:BAAANQADCgUICgAAAA==.',
Ai='Aisa:BAACNQAFFIEOAAQCAAYJUBqAAgDMAAADAAMJLBebBQAWAQACAAIJASKAAgDMAAAEAAEJWhTqAwBTAAA1AAQKgR0ABAIACQmnJDcIAFQCAAIABgkoIzcIAFQCAAMABgnlItUpADgCAAQAAQldJMMSAGoAAAAA.Aish:BAACNQAFFIEPAAIFAAYJVhlpAAA6AgAFAAYJVhlpAAA6AgA1AAQKgRUAAgUACQliJlwDAMIDAAUACQliJlwDAMIDAAAA.Aiso:BAAANQABCggIDQAAAA==.',
Ak='Akali:BAABNQAECoEsAAIGAAgJ7SYwAQCsAwAGAAgJ7SYwAQCsAwAAAA==.',
Al='Aldofio:BAAANQAECgQIBwAAAA==.Alhttabe:BAAANQAECgQICgAAAA==.Alvln:BAABNQAECoEgAAIHAAkJ9Rw7CAAdAwAHAAkJ9Rw7CAAdAwAAAA==.',
An='Andyrios:BAAANQADCggIDQAAAA==.',
Ap='Apoplectic:BAAANQAECgIIBAAAAA==.',
Ar='Aradinya:BAAANQADCggICAAAAA==.Arahat:BAAANQAECgEIAQAAAA==.Arakinya:BAAANQAECgYIBgAAAA==.Aralinya:BAABNQAECoEgAAMIAAkJThfvHgBSAgAIAAkJThfvHgBSAgAJAAgJVg2jFgD6AQAAAA==.Aratus:BAAANQAECgYIBgAAAA==.Ardentflame:BAAANQAECgUIBwAAAA==.Arindel:BAAANQADCgIIAgAAAA==.Arsoul:BAAANQADCgIIAgAAAA==.',
As='Asperonia:BAACNQAFFIEOAAIKAAYJ7AbfAQDbAQAKAAYJ7AbfAQDbAQA1AAQKgSAAAgoACQmmGUMQAOICAAoACQmmGUMQAOICAAAA.Asterisk:BAAANQAECgUIBgABNQAFFAYIDgACAFAaAA==.Astinous:BAAANQADCggICAAAAA==.Astlyr:BAAANQADCgIIAgAAAA==.Astrid:BAACNQAFFIEJAAILAAUJrg8xAwCbAQALAAUJrg8xAwCbAQA1AAQKgRsAAgsACQkFIg0DAFIDAAsACQkFIg0DAFIDAAAA.',
At='Athera:BAAANQADCgYIBgAAAA==.Atiermonk:BAAANQAECgEIAQAAAA==.',
Au='Auroral:BAABNQAECoEYAAIKAAgJOxAEKQAtAgAKAAgJOxAEKQAtAgAAAA==.Ausdemonic:BAAANQAECgEIAQAAAA==.',
Av='Avell:BAAANQAECggIEwAAAA==.',
Ax='Axiomatic:BAAANQADCgYIBgAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azriox:BAAANQADCgUIBQAAAA==.Azsharia:BAAANQADCgYIBgAAAA==.Azzielliea:BAAANQAECgYIEQAAAA==.',
Ba='Badumdadoom:BAAANQAECgMIAwABNQAFFAYICQAMAAwfAA==.Barleybrew:BAAANQADCgIIAgAAAA==.Battletank:BAAANQAECgQIBwABNQAECgkJIAAHAPUcAA==.',
Be='Beefchar:BAAANQAECgEIAQAAAA==.Beefquake:BAABNQAECoEaAAMNAAkJxxbVHABzAgANAAkJxxbVHABzAgAOAAIJ5BW1kgCOAAAAAA==.Betray:BAAANQAECgIIAgAAAA==.Beàr:BAAANQADCggIFAAAAA==.',
Bi='Bigbadbaka:BAACNQAFFIEOAAIPAAYJUR9DAQBeAgAPAAYJUR9DAQBeAgA1AAQKgSAAAg8ACQmeJTgCANsDAA8ACQmeJTgCANsDAAAA.Bigdecay:BAAANQAECgcIEAAAAA==.',
Bl='Blasez:BAAANQAECgUIBQAAAA==.Blazez:BAABNQAECoEhAAIFAAkJnCE6DABIAwAFAAkJnCE6DABIAwAAAA==.Blazpew:BAAANQADCggICAAAAA==.Blood:BAEANQAECgEIAQAAAA==.',
Bo='Bogart:BAABNQAECoEfAAMDAAkJvyG2DQD0AgADAAgJVSG2DQD0AgACAAQJjRzGHwA8AQAAAA==.Bomohdh:BAAANQAECgcIBgABNQAECgkJGAAPAC4bAA==.Bomohomo:BAABNQAECoEYAAIPAAkJLhvsJQC0AgAPAAkJLhvsJQC0AgAAAA==.Boogeymayne:BAAANQADCgIIAgAAAA==.Bootycallz:BAAANQAECgEIAQAAAA==.',
Br='Brainlag:BAAANQAECgIIAgAAAA==.Brawny:BAAANQAECgEIAQAAAA==.Brevren:BAAANQADCgMIAwABNQAECgYIDgAQAAAAAA==.Brevrin:BAAANQAECgYIDgAAAA==.',
Bu='Bubbix:BAAANQAECgMIAwAAAA==.Buddhatime:BAAANQADCgYIBgABNQAECggIEQAQAAAAAA==.Bui:BAABNQAFFIELAAIRAAYJaBSbAADyAQARAAYJaBSbAADyAQAAAA==.Buikia:BAAANQAFFAIIAgABNQAFFAYICwARAGgUAA==.Bunnyhop:BAAANQAECgIIAgAAAA==.Buysfeetpics:BAACNQAFFIEJAAISAAUJtA1xBgCtAQASAAUJtA1xBgCtAQA1AAQKgR8AAhIACQm8InENAHgDABIACQm8InENAHgDAAAA.',
['Bâ']='Bânê:BAAANQAECgYICwAAAA==.',
Ca='Calx:BAAANQAECgIIAgABNQAECgkJIAALACIXAA==.Camerõn:BAAANQADCgMIAwAAAA==.Cannicus:BAACNQAFFIELAAISAAYJ0g4UAwAHAgASAAYJ0g4UAwAHAgA1AAQKgSAAAhIACQlFJCwKAI0DABIACQlFJCwKAI0DAAAA.Cantheal:BAAANQADCgcIEAAAAA==.Capel:BAAANQADCgIIAgAAAA==.Cardinal:BAAANQAECgYIDAABNQAECggIEQAQAAAAAA==.',
Ce='Celavii:BAAANQAECgcIEQAAAA==.Celeena:BAAANQAECgMIAwAAAA==.',
Ch='Chamane:BAAANQAECgUIBwAAAA==.Chanengtotem:BAAANQADCgcIBwAAAA==.Chappell:BAAANQAECgEIAQAAAA==.Chii:BAAANQADCgEIAQAAAA==.Chillicheese:BAAANQADCgUIBwAAAA==.Chinnomojo:BAAANQAECgUIDQAAAA==.',
Ci='Cindermoon:BAAANQADCgYICwAAAA==.',
Cl='Cloudhorn:BAAANQAECgQIBgAAAA==.',
Co='Colena:BAEANQAECgcIEwAAAA==.Conquest:BAAANQAECgQIBAAAAA==.Conzy:BAAANQAECgQIBwAAAA==.Coopsfire:BAAANQADCgQIBQAAAA==.Corbulus:BAAANQAECgYIEwAAAA==.',
Cr='Create:BAAANQADCgcIBwABNQADCggIDQAQAAAAAA==.Crispyarrowz:BAAANQAECgEIAQABNQAECggIFgASAAMWAA==.Crispymage:BAABNQAECoEWAAISAAgJAxasUQBWAgASAAgJAxasUQBWAgAAAA==.',
Ct='Ctierwarlock:BAAANQAECgYIEgABNQAFFAYIDgATAF4lAA==.',
Cy='Cyndi:BAAANQAECgIIAgAAAA==.Cynxs:BAAANQAECgMIBQABNQAECgkJGAAUAIYaAA==.',
Da='Dahala:BAAANQADCgQIBAABNQAECgYIDwAQAAAAAA==.Dannoh:BAAANQAECgEIAQAAAA==.Darcious:BAAANQAECgIIAgABNQAECgcIEQAQAAAAAA==.Darkcinders:BAAANQAECgcIEQAAAA==.Davayer:BAAANQAECgUIBQAAAA==.',
De='Deadjkcocoon:BAAANQADCgMIBAAAAA==.Deadlly:BAAANQAECgUICgAAAA==.Deathbfbirth:BAAANQADCggICAABNQAECgQIBAAQAAAAAA==.Deathmage:BAAANQAECgMIAwABNQAECgkJHAAVAL4kAA==.Deathrocks:BAABNQAECoEcAAIVAAkJviQwAgDBAwAVAAkJviQwAgDBAwAAAA==.Demöníc:BAAANQAECgcIDwAAAA==.Deplock:BAAANQAECgUICAAAAA==.Destcrypt:BAAANQAECgEIAQABNQAECggIFgAWAN8iAA==.Destinyisall:BAAANQADCgYIBgAAAA==.Destwind:BAABNQAECoEWAAIWAAgJ3yJ1AwAnAwAWAAgJ3yJ1AwAnAwAAAA==.',
Di='Dilo:BAAANQADCggIBwAAAA==.Disbelief:BAAANQADCgEIAQAAAA==.Divinfinity:BAAANQAECgQICQAAAA==.',
Do='Doeji:BAAANQAECggIAwAAAA==.Dotdotseckz:BAAANQAECgYIEgAAAA==.',
Dr='Dracdoy:BAAANQAECgYICgAAAA==.Drethalis:BAAANQADCgUIGgAAAA==.Drewstormio:BAAANQAECgEIAQABNQAECgEIAQAQAAAAAA==.Dryene:BAAANQAECgIIAgAAAA==.',
Ds='Dsdh:BAACNQAFFIENAAIHAAYJ+xXgAAAsAgAHAAYJ+xXgAAAsAgA1AAQKgRcAAgcACQlnI18EAHADAAcACQlnI18EAHADAAAA.',
Du='Dulang:BAABNQAECoEWAAIBAAgJrB0LFgDIAgABAAgJrB0LFgDIAgAAAA==.',
Ea='Eattherich:BAAANQAECgMIAwAAAA==.',
Ec='Ectruby:BAABNQAECoEeAAMXAAkJlx3hAQA3AwAXAAkJlx3hAQA3AwATAAEJwg73cQAuAAAAAA==.',
El='Elammental:BAAANQADCgYIBgAAAA==.Elertricsoup:BAAANQAECgIIAgAAAA==.Elwarlocko:BAAANQAECgUIBgAAAA==.Elyndre:BAACNQAFFIEJAAQYAAUJARS0AwDpAAAYAAMJGRS0AwDpAAALAAEJ3QgDCgBXAAAZAAEJDgnyAwBUAAA1AAQKgR8ABBgACQkqHJkFAOkCABgACQl3GZkFAOkCABkAAwkCJCUIAEABAAsAAwmAHRAhAPgAAAAA.',
Em='Emberis:BAAANQADCgUIBQAAAA==.',
En='Endari:BAAANQAECgUIBQAAAA==.Endlockz:BAAANQAECgcIEAAAAA==.',
Er='Erikk:BAACNQAFFIEOAAIHAAYJtBElAQAKAgAHAAYJtBElAQAKAgA1AAQKgSAAAgcACQniIbMDAIEDAAcACQniIbMDAIEDAAAA.',
Es='Escher:BAAANQADCgUICwAAAA==.Esprit:BAAANQAECgQIBgABNQAFFAQIBwASAOwQAA==.',
Ex='Excalibur:BAAANQAECgEIAQAAAA==.',
Fa='Faeia:BAABNQAECoEhAAIaAAcJERnmDwAkAgAaAAcJERnmDwAkAgABNQAFFAYIBwANAFEcAA==.Faenirel:BAAANQAECgYIDAABNQAECgQIDQAQAAAAAA==.Faeya:BAACNQAFFIEHAAINAAQJURx1BwDVAAANAAQJURx1BwDVAAA1AAQKgR8AAw0ACQkOJVkGAFADAA0ACQkOJVkGAFADAA4ABAkeFhJgAC4BAAAA.Fairyen:BAAANQAECgUIDQAAAA==.Faithful:BAAANQAECgUIBgAAAA==.Faithless:BAAANQADCgQIBAAAAA==.Famine:BAAANQADCgUIBQABNQAECgUICAAQAAAAAA==.Farapanda:BAAANQADCgYICQAAAA==.Fastcharge:BAAANQAECgQIBgABNQAECgkJIAAHAPUcAA==.',
Fe='Feidutdut:BAAANQAECgYICAAAAA==.Feldown:BAAANQAFFAEIAQAAAA==.',
Ff='Ffdeathpunch:BAAANQADCgQIBAABNQAECgYIDgAQAAAAAA==.Ffen:BAAANQAECgYICgABNQAECgcIBwAQAAAAAA==.',
Fi='Fibanocci:BAABNQAECoEZAAISAAgJeBk6SgBvAgASAAgJeBk6SgBvAgAAAA==.Fierce:BAABNQAECoEaAAMYAAgJEhDmDQD6AQAYAAgJEhDmDQD6AQAZAAEJAANAFgAlAAAAAA==.Fixated:BAABNQAECoEZAAMDAAYJAgqOYwBDAQADAAYJAgqOYwBDAQACAAEJbADmZgAdAAAAAA==.',
Fl='Flamerage:BAAANQAECgYIBgAAAA==.',
Fr='Frankadelic:BAAANQAECgQIBwAAAA==.Frodolol:BAACNQAFFIEMAAMSAAYJ8hU9AgAnAgASAAYJjxU9AgAnAgAbAAEJTRSMAwBWAAA1AAQKgSEAAhIACQlrJGIKAIwDABIACQlrJGIKAIwDAAAA.Frostik:BAAANQAECgEIAQAAAA==.Frostyfruit:BAAANQAECgYICwAAAA==.',
Fu='Fufamace:BAAANQADCgIIAwAAAA==.Fufina:BAAANQADCgcIDwAAAA==.',
Fw='Fwoopie:BAAANQAECgcIDwAAAA==.Fwooplin:BAAANQAECgEIAwABNQAECgcIDwAQAAAAAA==.',
Ga='Gannina:BAAANQAECgcIEgAAAA==.Garage:BAAANQADCgEIAQAAAA==.',
Gi='Gillemon:BAAANQADCgQIBQAAAA==.Givre:BAAANQADCgIIAgAAAA==.Gizzy:BAAANQAECgQIDAAAAA==.',
Go='Goodra:BAAANQADCgYIBgABNQAECgkJIAAHAPUcAA==.Goodwill:BAAANQAFFAEIAQABNQAFFAEIAQAQAAAAAA==.',
Gr='Graoul:BAAANQAECgEIAQAAAA==.Greybeards:BAAANQADCgcICQAAAA==.Gritt:BAAANQADCggIFQAAAA==.Gryffin:BAAANQAECgUICgAAAA==.',
Gu='Gugudan:BAAANQAECgMIBgAAAA==.Gunnina:BAAANQADCggIDgAAAA==.Gutsc:BAABNQAECoEYAAIWAAkJxh+9AgBFAwAWAAkJxh+9AgBFAwAAAA==.Guyhulikatit:BAAANQADCggICAABNQAFFAUIBwAGAP0NAA==.Guzzan:BAAANQAECgEIAQABNQAECgQIBAAQAAAAAA==.',
Ha='Hatewatching:BAAANQAECgcIDgAAAA==.',
He='Healbòt:BAAANQAECgIIAgAAAA==.Hemorrhage:BAABNQAECoEbAAIcAAkJBxiJBwDOAgAcAAkJBxiJBwDOAgAAAA==.Hermighty:BAAANQAECgUIBgAAAA==.Hershéy:BAAANQAECgYICwAAAA==.Hert:BAAANQAECggIBAAAAA==.',
Hi='Hiradaira:BAAANQAECgMIBQAAAA==.',
Ho='Holasimón:BAAANQAECgQICgAAAA==.Hothotseckz:BAAANQAECgEIAQABNQAECgYIEgAQAAAAAA==.',
Hu='Hukk:BAAANQAECgYIDwAAAA==.',
Hy='Hypervoltage:BAAANQADCgMIAwAAAA==.Hypnos:BAAANQAECgYIBgAAAA==.',
['Hà']='Hà:BAAANQAECgUICQAAAA==.',
Ia='Iamundecided:BAAANQADCggIDQAAAA==.Iamzzr:BAAANQAECgQIBQAAAA==.',
Ic='Icysun:BAAANQAECgYICQAAAA==.',
Ig='Igneous:BAAANQAECgEIAQAAAA==.',
Im='Image:BAAANQADCgcIBwABNQADCggIDQAQAAAAAA==.Imnotamage:BAAANQADCgMIBgAAAA==.',
Is='Ish:BAAANQAECggIBgAAAA==.Isopod:BAAANQADCgYICAAAAA==.',
Ja='Jabbah:BAAANQAECgIIBAAAAA==.Jackee:BAAANQAECgQICQABNQAECgUICAAQAAAAAA==.Jasmean:BAABNQAECoEfAAMdAAkJKSKYCAAGAwAdAAgJACKYCAAGAwABAAMJYxWsmQDUAAAAAA==.',
Je='Jellybeanss:BAAANQAECgcIDgAAAA==.Jereu:BAAANQADCgYIBwAAAA==.',
Jo='Jodix:BAAANQADCgIIAgAAAA==.Johnevoker:BAAANQAECgYIBAABNQAECgkJGQANABgYAA==.Johnpaladin:BAAANQAECgYIBAABNQAECgkJGQANABgYAA==.Jombii:BAAANQAECgUIBwABNQAECgkJHQAGAOgTAA==.Jordoom:BAAANQAECgQIBQAAAA==.',
Ju='Judicas:BAAANQADCggIEAAAAA==.',
['Jë']='Jëwjuice:BAAANQABCgQIBAAAAA==.',
Ka='Kafra:BAAANQADCgYIBgABNQAECgUICAAQAAAAAA==.Kafrial:BAAANQAECgYIAwAAAA==.Kamazi:BAABNQAECoETAAIZAAgJ6ReeAwBGAgAZAAgJ6ReeAwBGAgAAAA==.Kannina:BAAANQAECgEIAQAAAA==.Kariiyon:BAAANQAECgIIAgAAAA==.Katalen:BAAANQADCgQIBQAAAA==.Kayapau:BAABNQAECoEXAAMOAAkJgxgMFgDJAgAOAAkJgxgMFgDJAgAUAAQJIwvTFwDhAAAAAA==.',
Ke='Kevd:BAAANQAECgYICgABNQAFFAYIEQANAPIcAA==.Kevin:BAACNQAFFIERAAINAAYJ8hyWAABdAgANAAYJ8hyWAABdAgA1AAQKgRwAAg0ACQlSJWMBALwDAA0ACQlSJWMBALwDAAAA.Kevp:BAAANQAECgYIBgABNQAFFAYIEQANAPIcAA==.',
Kh='Khaii:BAABNQAECoEeAAMSAAkJryTdBwCeAwASAAkJYiTdBwCeAwAbAAMJvCRMCwBCAQAAAA==.',
Ki='Kidevil:BAAANQAECgIIAgAAAA==.Kimmiereed:BAAANQAECgYIEgABNQAECggIJAAEAOwZAA==.',
Ko='Komai:BAABNQAECoEYAAMNAAkJ8B6vBgBLAwANAAkJ8B6vBgBLAwAOAAYJUx0ILQAWAgAAAA==.Kopikia:BAAANQAECgcIDgAAAA==.',
Kr='Krucify:BAAANQAECgYIBgAAAA==.',
Kt='Ktl:BAAANQAECgYIBgABNQAECgcIEgAQAAAAAA==.Ktw:BAAANQADCgEIAQABNQAECgcIEgAQAAAAAA==.Ktx:BAAANQAECgcIEgAAAA==.',
Ku='Kulak:BAAANQADCgUIBwABNQAECgcICQAQAAAAAA==.',
Ky='Kyall:BAABNQAECoEaAAMeAAgJpxwWDwCbAgAeAAgJpxwWDwCbAgAHAAEJZQyCSQA9AAAAAA==.',
La='Ladiesman:BAAANQAECggIBgAAAA==.Lafret:BAAANQADCggIDgAAAA==.Lamerzz:BAAANQADCgYIDwAAAA==.',
Le='Lebronyames:BAAANQAECgQIBQAAAA==.Lelith:BAAANQAECgYIEAAAAA==.Lerazar:BAAANQAECgEIAQAAAA==.Lettuce:BAAANQAECgIIAwAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Liquidvoid:BAAANQAECgcIEAAAAA==.Littleannie:BAAANQADCgQIBAAAAA==.',
Lu='Luurch:BAABNQAECoEfAAMcAAkJryPAAgBfAwAcAAgJ9CTAAgBfAwAGAAQJLRneIgBUAQAAAA==.',
Ly='Lynnae:BAAANQADCgUIBgABNQAECgcICQAQAAAAAA==.Lythillen:BAAANQADCgMIBAAAAA==.Lythium:BAAANQADCgMIAwAAAA==.',
['Lî']='Lîght:BAAANQAECgQIBAABNQAECgUICAAQAAAAAA==.',
Ma='Maceson:BAAANQADCggIDAAAAA==.Magikcreepz:BAAANQAECggICwAAAA==.Magnamund:BAAANQABCgYIDQAAAA==.Marvik:BAAANQADCgIIAgAAAA==.Masquerapet:BAACNQAFFIEOAAIfAAYJRRJkAgDHAQAfAAYJRRJkAgDHAQA1AAQKgSAAAh8ACQlHGUURALMCAB8ACQlHGUURALMCAAAA.Mavqt:BAAANQADCgIIAgAAAA==.',
Me='Megadeath:BAAANQAECggIDgAAAA==.Mentalas:BAAANQAECgUICgAAAA==.Mepuzzible:BAAANQAECgUIBQAAAA==.Meulah:BAAANQAECgUICAAAAA==.',
Mi='Miah:BAAANQAECggICwAAAA==.Miao:BAACNQAFFIEHAAINAAUJGBYgAgDKAQANAAUJGBYgAgDKAQA1AAQKgR4AAg0ACQlzJB0CAKgDAA0ACQlzJB0CAKgDAAE1AAUUBQgKABoAiRIA.Miaomiaomiao:BAACNQAFFIEKAAIaAAUJiRIxAQCkAQAaAAUJiRIxAQCkAQA1AAQKgR4AAhoACQmqH4gDADwDABoACQmqH4gDADwDAAAA.Miaomiaorawr:BAAANQAECgUICgABNQAFFAUICgAaAIkSAA==.Minamai:BAAANQAECgUIDAABNQAECgYIDwAQAAAAAA==.Misdirecting:BAAANQADCgYICgABNQADCggIDQAQAAAAAA==.',
Mo='Monggoloid:BAAANQADCgMIAwAAAA==.Monsieurstun:BAAANQADCgEIAQAAAA==.Moongrass:BAAANQAECgEIAQAAAA==.Mousemarâ:BAAANQAECgUICgAAAA==.',
Mu='Mungomania:BAAANQAECgQIBgAAAA==.Mutedz:BAABNQAECoEVAAIKAAkJag9nJQBCAgAKAAkJag9nJQBCAgAAAA==.',
Na='Nagaridar:BAAANQADCgUIBQAAAA==.Nargorr:BAAANQADCgYIDAAAAA==.Naruwa:BAAANQADCgMIAwAAAA==.',
Ne='Necroticlol:BAABNQAECoEfAAMVAAkJ/yKtBQB2AwAVAAkJ/yKtBQB2AwAgAAQJexhBKAAkAQAAAA==.Necroticlòl:BAAANQAECgYIDQABNQAECgkJHwAVAP8iAA==.Neeyana:BAAANQADCgcICQAAAA==.Neff:BAAANQAECgcIBwAAAA==.Nefpore:BAAANQAECgQIBQAAAA==.Nenepok:BAAANQADCgYIBgAAAA==.Nephelem:BAAANQADCgIIAgAAAA==.',
Ni='Niij:BAAANQAECgQIBQAAAA==.Nitox:BAAANQAECgIIAgAAAA==.',
No='Nopantiesx:BAAANQADCgcIBwAAAA==.Norielia:BAAANQADCgYICQAAAA==.Noruid:BAAANQADCgMIAwABNQAECgkJFgAPAPsWAA==.Nosivire:BAAANQAECgEIAQAAAA==.Nosok:BAAANQAECgIIBAABNQAECggIEwAQAAAAAA==.Notwiththema:BAAANQAECgUICgAAAA==.Noughtawolf:BAAANQAECgYIDAAAAA==.',
Nt='Nthope:BAAANQAFFAUICwAAAQ==.',
Od='Odîn:BAAANQADCggICQAAAA==.',
On='Onlyfire:BAAANQAECgYIBwAAAA==.Onlylight:BAAANQAECggIAgAAAA==.',
Pa='Palabean:BAAANQADCgUICQAAAA==.Patsie:BAAANQAECgYIBgAAAA==.',
Pe='Peach:BAAANQAECgMIAwABNQAFFAUICAAcAOwNAA==.Peeta:BAAANQADCgIIAgAAAA==.Pepperino:BAAANQADCgMIAwAAAA==.Perseph:BAAANQAECggIBwAAAA==.',
Ph='Phoebe:BAAANQADCgYIBgAAAA==.',
Pi='Piyona:BAAANQAECgQIBAAAAA==.',
Po='Pocketpie:BAAANQABCgYICwAAAA==.Poros:BAAANQADCgYIBgABNQAECgkJGQAVAPUdAA==.Porosdk:BAABNQAECoEZAAIVAAkJ9R1sCQA0AwAVAAkJ9R1sCQA0AwAAAA==.Poteb:BAAANQADCgUIBwAAAA==.Powerangers:BAAANQADCgIIAgAAAA==.',
Pr='Prevailor:BAAANQADCgUIAgAAAA==.Prodigal:BAABNQAECoEeAAIhAAkJVRMQBAA3AgAhAAkJVRMQBAA3AgAAAA==.',
Pt='Pterion:BAAANQAECgQICAAAAA==.',
Pu='Pumbz:BAAANQAECgQIBgAAAA==.Punprepared:BAEANQAECggICwAAAA==.',
Qe='Qeb:BAACNQAFFIEHAAIGAAUJ/Q3YAACqAQAGAAUJ/Q3YAACqAQA1AAQKgSAAAwYACQnVIM0DAD8DAAYACQnVIM0DAD8DABwABQkuEZAhAEsBAAAA.',
Qi='Qio:BAAANQABCgcICgAAAA==.Qisz:BAAANQAECgYICwAAAA==.',
['Qí']='Qíqi:BAAANQAECgcIEwAAAA==.',
Ra='Raincy:BAAANQADCgEIAQAAAA==.Rashes:BAAANQAECgQIBAAAAA==.Ratix:BAAANQAECgIIAgAAAA==.Ravenn:BAAANQAECgEIAQAAAA==.Razoxaynne:BAAANQAECgQIBQAAAA==.',
Re='Resolute:BAAANQADCgYIBgAAAA==.Reverb:BAAANQABCgIIAgABNQAECgYIGQADAAIKAA==.',
Rh='Rhyker:BAAANQAECgUICAAAAA==.',
Ri='Riinegan:BAAANQAECgMIAwAAAA==.Rimreaper:BAAANQAECgQIBAAAAA==.',
Ro='Rolypollie:BAAANQAECgEIAgAAAA==.Rorak:BAAANQADCgQICAABNQAECggIHgAiAIwQAA==.',
Ru='Ruptured:BAABNQAECoEbAAIGAAcJRyVeBgD1AgAGAAcJRyVeBgD1AgAAAA==.',
Ry='Ryndra:BAAANQADCgYIBgAAAA==.',
['Rä']='Räzoxane:BAAANQADCgIIAgAAAA==.',
Sa='Satria:BAAANQADCggIDwAAAA==.Saveth:BAAANQAECgMIAwAAAA==.',
Sc='Scamdawg:BAAANQADCgYIBgAAAA==.Screamin:BAAANQADCgEIAQAAAA==.Scumdawg:BAAANQADCgQIBAAAAA==.',
Sh='Shadesong:BAAANQAECgIIAgAAAA==.Shadowboiz:BAAANQAECgcIEgAAAA==.Shamdoy:BAAANQAECgUICQABNQAECgYICgAQAAAAAA==.Shampagne:BAAANQAECgEIAQABNQAECgYIGQADAAIKAA==.Shapeshiift:BAAANQADCgYIBgAAAA==.Shidann:BAACNQAFFIEOAAITAAYJXiVsAACnAgATAAYJXiVsAACnAgA1AAQKgSAAAhMACQn4JgsAABgEABMACQn4JgsAABgEAAAA.Shiifty:BAAANQADCgIIBAAAAA==.Shintopal:BAAANQAECgUICQAAAA==.Shintoslash:BAAANQAECgUIBQAAAA==.Shopgirl:BAAANQADCgYIBgAAAA==.',
Si='Silentsnipe:BAAANQADCggICAAAAA==.Silverdeath:BAAANQAECgcIDgAAAA==.Silvermaiden:BAAANQABCgIIAgAAAA==.Sinorph:BAAANQAECgcIEwAAAA==.',
Sl='Slappuccino:BAAANQAECgQIBgAAAA==.Sleeptime:BAAANQAECggIEQAAAA==.',
Sn='Sneakyitch:BAAANQAECgUICQAAAA==.Snipez:BAAANQADCgQIBAABNQAFFAEIAQAQAAAAAA==.',
So='Soggybiscuit:BAAANQAECgEIAQAAAA==.Soil:BAABNQAECoEgAAMLAAkJIhffDABeAgALAAkJIhffDABeAgAYAAUJxgkdGgAGAQAAAA==.Solanaz:BAAANQAECgEIAQAAAA==.Somepally:BAAANQAECgcICgABNQAECgQIDQAQAAAAAA==.Sorahal:BAAANQADCgEIAQAAAA==.',
Sp='Spagalnero:BAAANQAECgEIAQAAAA==.Spinnywinny:BAAANQAECgEIAQAAAA==.',
St='Stampedê:BAAANQADCggIDgAAAA==.Stan:BAACNQAFFIEIAAMBAAQJCBTxBgC/AAAdAAMJLRCFCADcAAABAAIJ7hfxBgC/AAA1AAQKgSIAAwEACQm0JFsGAGoDAAEACAnBJVsGAGoDAB0ACAnpHMMQAHkCAAAA.Stanstanstan:BAAANQAECggICAABNQAFFAQICAABAAgUAA==.Starleet:BAAANQADCgIIAgAAAA==.Stier:BAAANQADCgQIBAABNQADCggIDQAQAAAAAA==.Stiggyy:BAAANQAECgQIBQAAAA==.Stiria:BAAANQAECgQIBwAAAA==.Stormscythe:BAAANQAECgIIAgAAAA==.',
Su='Supercleave:BAAANQADCggIEAAAAA==.Superdope:BAAANQADCgcIDgAAAA==.Superfly:BAAANQAECgQIBgAAAA==.Supermayhem:BAAANQADCgQIBQAAAA==.Suspense:BAAANQABCgYIBgAAAA==.Sutiao:BAABNQAECoEeAAISAAkJQCR3BgCqAwASAAkJQCR3BgCqAwAAAA==.',
Sw='Swissarmy:BAAANQADCgcICgAAAA==.Switchknife:BAAANQAECggIDgAAAA==.',
Sy='Sylasiana:BAAANQAECgEIAQAAAA==.Synasta:BAABNQAECoEeAAQDAAkJ/yF/CwAJAwADAAgJvCJ/CwAJAwACAAcJfh1RBwBrAgAEAAEJlgf/GABEAAABNQAECgkJFwAVADEfAA==.Syrent:BAAANQAECgQICAAAAA==.',
Ta='Taano:BAAANQADCgUICwAAAA==.Tallia:BAAANQAECgQIBAABNQAECgYIHwASAL4dAA==.Talons:BAAANQAECgQIBgAAAA==.Tamed:BAAANQADCgQIBAAAAA==.Tancs:BAAANQAECgMIAwAAAA==.Tarocakes:BAABNQAECoEaAAMZAAkJlwleCAA1AQAZAAcJSgheCAA1AQALAAgJlwDCLQBdAAAAAA==.Taurium:BAAANQAECgcIEwAAAA==.',
Te='Teaki:BAAANQAECgYIEQAAAA==.Telsh:BAAANQAECggIDwAAAA==.Temsik:BAAANQAECgYIDwAAAA==.Temsikdab:BAAANQADCgMIAwAAAA==.',
Th='Thoth:BAABNQAECoEcAAQDAAkJQRoMSgCjAQADAAYJkBgMSgCjAQACAAMJuRUmLQDeAAAEAAIJ/xpdDgCnAAAAAA==.Thrallish:BAAANQADCgcIDAAAAA==.Thrux:BAAANQAECgYIDAAAAA==.Thura:BAAANQAECgEIAQAAAA==.',
Ti='Tidal:BAAANQAECgMIAwABNQAECgUICAAQAAAAAA==.Tiddlyniblit:BAAANQADCgcIEwAAAA==.',
To='Tommyh:BAACNQAFFIENAAIJAAYJ2BlyAABGAgAJAAYJ2BlyAABGAgA1AAQKgSAAAgkACQkxJX8BALwDAAkACQkxJX8BALwDAAAA.Topuzzible:BAAANQAECgEIAQABNQAECgUIBQAQAAAAAA==.Torress:BAAANQAECgUIBQAAAA==.Totemistyk:BAAANQAECggIDAAAAA==.Toufz:BAABNQAECoEXAAMdAAkJ8BlkFgAnAgAdAAgJ2BRkFgAnAgABAAQJWiBtXgCDAQAAAA==.',
Tr='Trianth:BAAANQAECgYIDwAAAA==.Tribbie:BAABNQAECoEXAAQVAAkJlh7CEgC7AgAVAAgJ1h/CEgC7AgAgAAEJlBQpSgBIAAAfAAEJgREgggAzAAAAAA==.Tribbier:BAAANQAFFAIIAgAAAA==.',
Tw='Twidger:BAAANQAECgEIAQAAAA==.',
Ty='Tyranadia:BAABNQAECoEfAAIVAAkJIBdNFQChAgAVAAkJIBdNFQChAgAAAA==.Tystus:BAAANQAECgIIAgAAAA==.',
Um='Um:BAAANQAECgEIAQAAAA==.',
Up='Upstairs:BAABNQAECoEZAAINAAkJGBiXFQCqAgANAAkJGBiXFQCqAgAAAA==.',
Ur='Uruga:BAAANQAECgEIAQAAAA==.',
Va='Varnoxx:BAABNQAECoEfAAIVAAkJKiGRBQB5AwAVAAkJKiGRBQB5AwAAAA==.',
Vi='Vicioûs:BAAANQAECgUICwAAAA==.Vinkwink:BAAANQADCgYIBgAAAA==.Vinwink:BAAANQADCgYIBgAAAA==.Vishnar:BAABNQAECoEWAAIDAAgJdhTpIQBlAgADAAgJdhTpIQBlAgAAAA==.',
Vo='Vollic:BAAANQADCggICAAAAA==.',
Vv='Vvoo:BAAANQAECgEIAQAAAA==.',
Vy='Vyndish:BAAANQAECgQIBAAAAA==.',
Wa='Wander:BAAANQAECgQICwAAAA==.Wardz:BAAANQADCgYICwAAAA==.Watever:BAAANQAECggICgAAAA==.Wavedash:BAAANQAECgQIBQAAAA==.Wazaldin:BAAANQADCgUICAAAAA==.',
We='Wendell:BAAANQADCgQIBAAAAA==.Wetpantees:BAAANQADCgcIBwAAAA==.',
Wh='Whispess:BAAANQAECgIIAgAAAA==.',
Wi='Winnievoid:BAAANQAECgYIDAAAAA==.',
Wo='Woodro:BAAANQAECgYIEgAAAA==.Woz:BAAANQAECgQIBAAAAA==.',
Xa='Xahara:BAAANQADCggICAAAAA==.',
Xl='Xln:BAAANQAECgMIBAABNQAECgYIDwAQAAAAAA==.',
Xt='Xtion:BAABNQAECoEeAAMdAAkJ3SRhAgCYAwAdAAkJ9yNhAgCYAwABAAIJ0yEIoAC7AAAAAA==.',
Ya='Yagnatia:BAAANQAECgUIBgAAAA==.',
Yo='Yongbok:BAAANQAECgEIAQAAAA==.',
Yr='Yrano:BAAANQAECgQIBQAAAA==.',
Yv='Yva:BAAANQADCggIBAAAAA==.',
Za='Zapu:BAAANQADCgUIBQAAAA==.Zaraxes:BAAANQADCgMIBQAAAA==.',
Ze='Zelgaira:BAABNQAECoEXAAIVAAkJMR9ZCwAYAwAVAAkJMR9ZCwAYAwAAAA==.Zelind:BAAANQADCgUIBwABNQAECgYIEAAQAAAAAA==.Zelvaris:BAACNQAFFIEJAAIMAAYJDB8LAABUAgAMAAYJDB8LAABUAgA1AAQKgScAAgwACQkfJTgAANwDAAwACQkfJTgAANwDAAAA.Zenõ:BAAANQAFFAEIAQAAAA==.Zerine:BAAANQAECgEIAgAAAA==.Zerkerman:BAAANQADCgcIBwAAAA==.',
Zi='Zirka:BAABNQAECoEfAAISAAYJvh3NZwAPAgASAAYJvh3NZwAPAgAAAA==.Zivayhr:BAAANQADCgEIAQAAAA==.',
Zu='Zucchini:BAAANQADCgYICAAAAA==.',
Zy='Zylexo:BAAANQABCgYIBgAAAA==.',
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
