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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Warrior-Fury','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Havoc','Warlock-Affliction','Rogue-Subtlety','Monk-Mistweaver','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-10-20',data={Ae='Aelithsong:BAEANQAECgYIDgABNQAECgUIBgABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8iAAICAAoKDA8tFAALAgACAAoKDA8tFAALAgAAAA==.',
Al='Alakthon:BAAANQABCgMIBAAAAA==.Alderok:BAAANQAECggIBgABNQAECgkJGgADAKgWAA==.Aliancia:BAABNQAECn8hAAIEAAgKIBTuBQBjAQAEAAgKIBTuBQBjAQAAAA==.Allusive:BAAANQADCgYIAwABNQAECgYIEQABAAAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgUIBQAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECn8sAAIFAAkKth9YHwDzAgAFAAkKth9YHwDzAgAAAA==.Annorca:BAAANQADCgQIBAABNQAECgkJLAAFALYfAA==.Antherina:BAAANQADCgEIAQAAAA==.Antonious:BAAANQAECgYICgAAAA==.',
Ap='Apollyon:BAABNQAECn86AAMGAAoKXiH7AQAXAwAGAAoKXiH7AQAXAwAHAAgKnxqoHgBwAQAAAA==.',
Ar='Ari:BAABNQAECn8iAAIIAAcKRyNrHQCaAQAIAAcKRyNrHQCaAQAAAA==.Ariioch:BAAANQAECgcIDAAAAA==.Arodar:BAAANQADCgMIAwAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgIIAgAAAA==.Assclapiuss:BAABNQAECn80AAMGAAoKTyREAwDgAgAGAAoKTyREAwDgAgAHAAQKSxAEzgDfAAAAAA==.Asterchades:BAABNQAECn87AAIJAAoKzxJwBADMAQAJAAoKzxJwBADMAQAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn8xAAIKAAgKGgftEwBrAQAKAAgKGgftEwBrAQAAAA==.Atuan:BAAANQAECgYICwAAAA==.',
Au='Auralass:BAAANQAECgMICAAAAA==.Autauga:BAAANQAECgcIDAAAAA==.',
Av='Avatard:BAAANQAECgQIBgABNQAECgoKJwAIANMOAA==.Avilla:BAABNQAECn8gAAIFAAkKkh3eMACkAgAFAAkKkh3eMACkAgAAAA==.',
Ax='Axem:BAABNQAECn8gAAIDAAkKLBdGCgAoAgADAAkKLBdGCgAoAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAABNQAECn8YAAMLAAcK2xFLGADrAAALAAYKxBRLGADrAAAMAAIKMwatGQAvAAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.Batryxamat:BAAANQAECgMIAwAAAA==.',
Be='Bechett:BAABNQAECn8gAAINAAkKaBLXKgDFAQANAAkKaBLXKgDFAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgUIBgAAAA==.Behemothe:BAABNQAECn89AAIOAAoKiRgTAQCTAgAOAAoKiRgTAQCTAgAAAA==.Berníesandrs:BAAANQAECgUIDQAAAA==.Beryllos:BAAANQADCggIFwAAAA==.Bewzey:BAABNQAECn8bAAIIAAoKnwwwxgD4AQAIAAoKnwwwxgD4AQAAAA==.',
Bh='Bhadabing:BAAANQAECgIIAQAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgMIAwAAAA==.',
Bl='Bleaugro:BAAANQADCggICAAAAA==.Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8gAAIPAAYK7CJICACsAQAPAAYK7CJICACsAQAAAA==.Bloodytoutii:BAAANQAECgUICgAAAA==.',
Bo='Bortman:BAABNQAECn8oAAILAAoKgCEABADlAQALAAoKgCEABADlAQAAAA==.Boukz:BAAANQADCgcIBgAAAA==.Bowowner:BAAANQAECgYIEwAAAA==.',
Br='Brazken:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIGAAYKOho9nwDjAQAGAAYKOho9nwDjAQAAAA==.Buzzball:BAABNQAECn8UAAIGAAYK8RLszwB7AQAGAAYK8RLszwB7AQAAAA==.',
Bw='Bwicked:BAABNQAECn8zAAMKAAoKbg7CFABeAQAKAAcKQhHCFABeAQAIAAoKRgwcVgARAQAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAECgoKNgAKAIcmAA==.',
Ce='Celonge:BAAANQAECgUIBgABNQAECgoKNwAHAOQYAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAIAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Chimpnzthat:BAAANQAECgQIDAAAAA==.Chookicookie:BAABNQAECn80AAMQAAoKeyG+EgAzAwAQAAoKeyG+EgAzAwARAAcKdxeyIwAtAQAAAA==.Chrome:BAABNQAECn87AAMSAAoKSh7sFgCLAgASAAgKyBzsFgCLAgATAAoKmhinAgBuAgAAAA==.',
Ci='Cici:BAAANQABCggIDQAAAA==.Cindyy:BAAANQAECggIHgAAAQ==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn8oAAIUAAoKSB9DGgDcAgAUAAoKSB9DGgDcAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgcIEQABAAAAAA==.Coresh:BAABNQAECn8wAAIOAAkKpxtECgDPAgAOAAkKpxtECgDPAgAAAA==.Cornpuff:BAAANQAECgcIDAAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAABNQAECn8VAAIIAAYKlwqaJAFOAQAIAAYKlwqaJAFOAQAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgQIDAABNQAECgoKNAAGAE8kAA==.Daemonbane:BAAANQADCgYIBgAAAA==.Damessiah:BAAANQAECgYICwAAAA==.Dark:BAABNQAECn81AAIVAAoK9yGTAgDJAgAVAAoK9yGTAgDJAgAAAA==.Darkphyre:BAAANQAECgcIDQAAAA==.Darthtree:BAAANQAECgUIBQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn80AAMVAAoKgyPGBQChAwAVAAoKgyPGBQChAwAWAAEK+h2XbABGAAAAAA==.Deathtike:BAABNQAECn8uAAIUAAgKsB9SDgByAQAUAAgKsB9SDgByAQABNQAECgoKOwAMAP0jAA==.Decius:BAAANQAECgcIDQAAAA==.Deltairlines:BAACNQAFFH8OAAMXAAUK8SBzAwDYAQAXAAUK8SBzAwDYAQAYAAEKXgCjGwAiAAA1AAQKfyAABBcACQp6IeMCABwDABcACQp6IeMCABwDABgACQo2EXAbABICAAIAAQqBDQw9ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUIDgAXAPEgAA==.Demagorgin:BAAANQAECgcIEgAAAA==.Deqlyn:BAABNQAECn8gAAIGAAgKShyHZABtAgAGAAgKShyHZABtAgAAAA==.Desmus:BAAANQAECgMIDAAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn8sAAIZAAkKgxt/GAAzAgAZAAkKgxt/GAAzAgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAABNQAECn8oAAIVAAkKARv1CgD7AQAVAAkKARv1CgD7AQAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doxophil:BAAANQAECgMIAwABNQAECggIFgAHACwVAA==.',
Dr='Dragonfloss:BAAANQAECggIBAAAAA==.Droax:BAAANQADCgYIBQAAAA==.Droh:BAAANQADCgcIBwAAAA==.Dronin:BAABNQAECn8nAAIaAAgKmBaNBwBtAQAaAAgKmBaNBwBtAQAAAA==.Drpatan:BAAANQAECgQICgAAAA==.Druni:BAAANQAECgcIDQAAAA==.Drâkenhân:BAAANQAECgcIDAAAAA==.',
Du='Dumpling:BAAANQADCgQIBAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMICwAAAA==.',
Ed='Edinburger:BAAANQADCgcIGwAAAA==.',
Eh='Ehdawg:BAAANQAECgQICQAAAA==.',
Ei='Eiduartrawr:BAAANQAECgEIAQAAAA==.Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQABCgMIAwAAAA==.',
El='Elguezo:BAAANQAECgMIBgAAAA==.Ellynna:BAAANQADCgcIBwAAAA==.',
Em='Emokillaz:BAAANQAECgUICQAAAA==.',
Ep='Epictaxes:BAAANQAECgUICQAAAA==.Epsilón:BAEANQAECgUIBgAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAABNQAECn8hAAIbAAkK/Br9TACHAgAbAAkK/Br9TACHAgAAAA==.',
Fe='Feronnia:BAAANQADCggIFwAAAA==.',
Fi='Fibot:BAABNQAECn87AAIOAAoKWRWQAQBeAgAOAAoKWRWQAQBeAgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQICAAAAA==.Fistavus:BAAANQABCgQIBAAAAA==.',
Fl='Florasol:BAAANQAECgQIBgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAAANQAECggIDgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAAANQAECgUIEwABNQAFFAUIEAAcANclAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIIAAgKaQ6cxgD3AQAIAAgKaQ6cxgD3AQAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgoKKQALAOARAA==.',
Gh='Ghomertin:BAAANQAECgMICAAAAA==.',
Gi='Gipsydanger:BAABNQAECn81AAMFAAoKISKqBgCGAgAFAAoKISKqBgCGAgAdAAIKKw1YIABfAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECgoKGwAIAKUFAA==.',
Go='Gonnjass:BAAANQADCgYIEwAAAA==.Goragar:BAAANQAECgQIBAAAAA==.Gorlokk:BAEANQADCgcICAAAAA==.',
Gr='Grakonys:BAABNQAECn8wAAICAAoK9wgZAwCKAQACAAoK9wgZAwCKAQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQICgAAAA==.Grunch:BAAANQADCgUICwAAAA==.Grunnck:BAAANQADCggIKgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAYIGQABAAAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQADCggIEAAAAA==.Harnix:BAAANQAECgMICgAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn8oAAIFAAoKGB86JADbAgAFAAoKGB86JADbAgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgYIFAAGAPESAA==.',
He='Hellreines:BAACNQAFFH8FAAIeAAIK6RxWCQCOAAAeAAIK6RxWCQCOAAA1AAQKfzgAAh4ACgodIRsBAPgCAB4ACgodIRsBAPgCAAAA.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgMIDAAAAA==.Him:BAAANQAECgUIDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8rAAIFAAgKxSTdEQA6AwAFAAgKxSTdEQA6AwAAAA==.Holyscales:BAAANQAECgUICwAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Id='Idarae:BAAANQAECgUICAABNQAECgoKKAAUAEgfAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAAANQAECgUICgAAAA==.',
Iv='Ivvy:BAAANQAECgUICQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECn8VAAIfAAkKvwguQQDHAQAfAAkKvwguQQDHAQAAAA==.Janntro:BAABNQAECn8lAAMgAAgKARdCFQBCAQAgAAgKARdCFQBCAQAMAAEKAADPLQBKAAABNQAECgkJIAAJAHYiAA==.Jantra:BAAANQADCgQIBAABNQAECgkJIAAJAHYiAA==.Jantro:BAABNQAECn8gAAIJAAkKdiKbBgAlAwAJAAkKdiKbBgAlAwAAAA==.Janttro:BAAANQAECgUIDwABNQAECgkJIAAJAHYiAA==.',
Je='Jebby:BAABNQAECn8mAAIIAAoKwhTpFwCwAQAIAAoKwhTpFwCwAQAAAA==.Jeebz:BAAANQAECgUICAABNQAECgoKJgAIAMIUAA==.Jelmarr:BAAANQADCggIFwAAAA==.Jerauld:BAAANQAECgMIDAAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8jAAIeAAgKOBj6CQC8AQAeAAgKOBj6CQC8AQAAAA==.Joshc:BAABNQAECn8hAAIJAAYKeQeUHQCkAAAJAAYKeQeUHQCkAAAAAA==.',
Jt='Jt:BAACNQAFFH8qAAQVAAkK7B/kAADNAgAVAAgK+CDkAADNAgAWAAIKEyMvBwC4AAAhAAIKCBmwAwC3AAA1AAQKfykAAxYACgrzJXIFAMECABUACArqJVwqANsCABYACAqYH3IFAMECAAAA.',
Ju='Judgédred:BAAANQAECggICQAAAA==.',
['Já']='Ják:BAABNQAECn8WAAMHAAgKLBU9WgAKAgAHAAgKLBU9WgAKAgAGAAEK/gsJAQEvAAAAAA==.',
Ka='Kaaris:BAABNQAECn8YAAIWAAgKnASBJQBIAQAWAAgKnASBJQBIAQAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kairos:BAABNQAECn82AAIIAAoK/A2uDwDqAQAIAAoK/A2uDwDqAQAAAA==.Kanofworms:BAABNQAECn8UAAIiAAgKNAgUKQC8AAAiAAgKNAgUKQC8AAAAAA==.Karkea:BAABNQAECn8YAAIUAAgKBCICEQAlAwAUAAgKBCICEQAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8kAAIEAAcKnRhJBgBYAQAEAAcKnRhJBgBYAQAAAA==.',
Ki='Kibil:BAABNQAECn8gAAMGAAkKMQ+ZjwAGAgAGAAgKWBGZjwAGAgAZAAEKRwJCPgAhAAAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8hAAIYAAYKExyyAwDKAQAYAAYKExyyAwDKAQAAAA==.Kos:BAACNQAFFH8QAAIcAAUK1yWjBAD+AQAcAAUK1yWjBAD+AQA1AAQKfyUAAhwACgoMJhkCADUCABwACgoMJhkCADUCAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgkJIAAJAHYiAA==.',
Ku='Kujiera:BAABNQAECn8dAAMWAAkKaAdeJgBCAQAWAAcKzwVeJgBCAQAVAAgKQQbhZAC5AAAAAA==.Kurick:BAAANQAECgYIEQAAAA==.Kurrenter:BAABNQAECn8gAAIHAAkKyRzXKgC8AgAHAAkKyRzXKgC8AgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn8xAAIZAAoKqw5sCwBFAQAZAAoKqw5sCwBFAQAAAA==.',
La='Laiyth:BAABNQAECn8mAAIVAAoKcg4MXwA6AgAVAAoKcg4MXwA6AgAAAA==.Larryfish:BAABNQAECn8iAAMPAAkKLSL0KACVAgAPAAcK4iL0KACVAgAeAAgKrR8yIwB2AgAAAA==.Lavos:BAABNQAECn8mAAIWAAkKPQwZFgC8AQAWAAkKPQwZFgC8AQAAAA==.',
Le='Levitikus:BAAANQAFFAEIAQAAAA==.',
Li='Lisster:BAABNQAECn8hAAIbAAYKTCLREQDiAQAbAAYKTCLREQDiAQAAAA==.Liyra:BAAANQAECgcIEQAAAA==.',
Lo='Loafe:BAABNQAECn8nAAIGAAoKeRRwQgBBAQAGAAoKeRRwQgBBAQAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgcIDQAAAA==.Luxury:BAABNQAECn8jAAIEAAgK7wOkEgChAAAEAAgK7wOkEgChAAAAAA==.',
Ly='Lykanthropos:BAAANQAECgIIAgAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn8fAAIiAAkKzw3LHAD+AAAiAAkKzw3LHAD+AAAAAA==.Mako:BAABNQAECn8uAAIYAAoKrB/aAgD5AQAYAAoKrB/aAgD5AQAAAA==.Malevian:BAAANQADCgYIMAAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn8zAAIjAAkK7Au2HgCfAQAjAAkK7Au2HgCfAQAAAA==.Marc:BAAANQAECgUICgAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAAANQAECgYIDgAAAA==.Mazz:BAABNQAECn8UAAIWAAgKuhP3EgDbAQAWAAgKuhP3EgDbAQAAAA==.',
Me='Megana:BAAANQADCgYIBgAAAA==.Megaterium:BAABNQAECn8ZAAIFAAgK6gvsjgBpAQAFAAgK6gvsjgBpAQAAAA==.Meláni:BAAANQAECgIIBAAAAA==.Menethil:BAAANQAECgYIEwAAAA==.',
Mi='Milei:BAAANQAECgcICAAAAA==.Misie:BAAANQABCgIIAQAAAA==.Missmisery:BAABNQAECn8dAAMbAAkKPg+0dAAmAgAbAAkKPg+0dAAmAgAkAAQK2ggaDgDMAAAAAA==.Mistaya:BAABNQAECn8gAAIQAAcK2AcJTwDBAAAQAAcK2AcJTwDBAAAAAA==.Mithdraug:BAAANQAECgcIDQAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAABNQAECn8hAAIlAAgKMgebSAAPAQAlAAgKMgebSAAPAQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECgIIAwAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
Mu='Mugzee:BAAANQAECgIIAQAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgQIBAAAAA==.',
['Mà']='Màtch:BAAANQADCgcICQABNQAECgoKJwAHAOcaAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAYIGQACACYjAA==.',
Ni='Nightparade:BAAANQAECgcIDQAAAA==.Nishgrail:BAABNQAECn8mAAMJAAgK3SNKBgAtAwAJAAgK3SNKBgAtAwATAAEKbQxiSwBCAAAAAA==.',
No='Nohkal:BAAANQADCgcIFgAAAA==.',
Nu='Nukusmaximus:BAAANQAECgMIDAAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAABNQAECn8UAAIGAAcK+RhLrQDFAQAGAAcK+RhLrQDFAQAAAA==.',
On='Onex:BAAANQAECgcIDQAAAA==.',
Or='Orangethanos:BAAANQADCggICAAAAA==.Orgrím:BAAANQAECgIIAQAAAA==.Ori:BAAANQAECgQIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAIjAAcKBAwBJwA+AQAjAAcKBAwBJwA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8iAAMRAAgKCw1EkgB3AQARAAcK4ApEkgB3AQAQAAEKtAE7pAAnAAAAAA==.Persefini:BAAANQAECggIDgAAAA==.Petrodaear:BAAANQADCgEJAQABNQADCggIGwABAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAAANQAECgcIDQAAAA==.Philidox:BAAANQADCgYIBgABNQAECggIFgAHACwVAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQAECgIIAQAAAA==.Plugugly:BAABNQAECn8eAAIbAAoKmhy5OQC9AgAbAAoKmhy5OQC9AgAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Popita:BAAANQAECgQIBwAAAA==.Portal:BAAANQADCgIIAgABNQAECggIHAAFALYTAA==.Potatobear:BAABNQAECn8vAAMbAAoK7yPLBACIAgAbAAoK7yPLBACIAgAaAAMKwRK4WwC2AAAAAA==.',
Pr='Praytwothee:BAABNQAECn8dAAIcAAoKfBwWDQAaAwAcAAoKfBwWDQAaAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn8yAAQgAAkKdhOhMgAWAgAgAAkKdhOhMgAWAgALAAYK7gj2RwAVAQAMAAEK1AnnNAAoAAAAAA==.',
Ra='Ragedh:BAABNQAECn8tAAILAAoKaCRpAQDZAwALAAoKaCRpAQDZAwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragna:BAAANQADCggICAAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAABNQAECn8WAAIbAAYKsRoDJwB+AQAbAAYKsRoDJwB+AQAAAA==.Ravensblood:BAAANQAECgcIDAAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECgcICQAAAA==.Reeses:BAEANQADCgYIDwABNQADCgcICAABAAAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDgAAAA==.Roglof:BAABNQAECn8bAAIIAAoKpQUXhwC2AAAIAAoKpQUXhwC2AAAAAA==.Rowlah:BAAANQAECgMICgAAAA==.Rozy:BAABNQAECn87AAMHAAoK/Rn/EADNAQAHAAkKqBr/EADNAQAGAAgKbBRfrwDAAQAAAA==.',
Ru='Ruiizu:BAABNQAECn8hAAIGAAYK4SC9KACFAQAGAAYK4SC9KACFAQAAAA==.Ruldas:BAAANQADCgYIBgAAAA==.Rushuna:BAABNQAECn8uAAIdAAoKexopAADpAgAdAAoKexopAADpAgAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAIbAAcKDRLjngDJAQAbAAcKDRLjngDJAQAAAA==.Sairicck:BAABNQAECn8oAAIbAAcKrhiNLwBiAQAbAAcKrhiNLwBiAQAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgcIDQAAAA==.',
Se='Selinora:BAAANQAECggIDQAAAA==.Senaria:BAAANQADCgIIAQAAAA==.Serhalatath:BAAANQAECgUIBgAAAA==.',
Sh='Shade:BAABNQAECn8cAAMFAAgKthNxbQDWAQAFAAgKthNxbQDWAQAdAAEKQBKaJwA3AAAAAA==.Shadonymph:BAAANQAECgQIBAAAAA==.Shadowsbane:BAABNQAECn8hAAMHAAcKUBP8dAC4AQAHAAcKUBP8dAC4AQAGAAQKCQvTKAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIGAAcKriKdXACCAgAGAAcKriKdXACCAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Shamwow:BAABNQAECn8mAAIRAAoKdSH4BgD5AQARAAoKdSH4BgD5AQAAAA==.Shaolinsnake:BAAANQAECggIDgAAAA==.Sharpspoon:BAAANQAECgMIAwABNQAECgoKNgAKAIcmAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgcIEQAAAA==.Shiiva:BAAANQAECgUIBQAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQAECgYIBgAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8nAAIIAAoK0w5tJwB6AQAIAAoK0w5tJwB6AQAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAABNQAECn8oAAIFAAcKdSIsCgBBAgAFAAcKdSIsCgBBAgAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgoKNwAHAOQYAA==.Solsti:BAABNQAECn83AAIHAAoK5Bh2FACwAQAHAAoK5Bh2FACwAQAAAA==.Soulhunter:BAACNQAFFH8GAAIUAAMKkBckGwDAAAAUAAMKkBckGwDAAAA1AAQKfyIAAxQACAo7IqMbANICABQACAo7IqMbANICAA8AAgqJIlGiALcAAAAA.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgcIBwAAAA==.Spoonbrew:BAAANQADCgUIBQABNQAECgoKNgAKAIcmAA==.Spoondot:BAAANQAECgUIBQABNQAECgoKNgAKAIcmAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIAwAAAA==.Stillthorny:BAAANQAECgIIAwAAAA==.Stinjaga:BAABNQAECn8hAAMIAAYKaht+ZwDuAAAIAAYKSBt+ZwDuAAAKAAIK8xgjDwCZAAAAAA==.Stormyknight:BAAANQAECgUIBAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAABNQAECn8UAAIbAAgK7BTFQQAyAQAbAAgK7BTFQQAyAQABNQAECgkJFQAfAL8IAA==.',
Su='Sunrae:BAAANQAECgMIDAAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgcIEwAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAIAGkOAA==.Taryen:BAABNQAECn8fAAIUAAgK9Qv/WgCGAQAUAAgK9Qv/WgCGAQABNQAECgoKLQALAGgkAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAECgoKJwAHAOcaAA==.Telaari:BAAANQAECgUIBwAAAA==.Telrander:BAAANQAECgIIAQAAAA==.Teriyl:BAABNQAECn8sAAMEAAoKLhQ8GgCSAQAlAAoKRQ7DhAAQAgAEAAUKXRs8GgCSAQAAAA==.',
Th='Thalenia:BAABNQAECn8tAAIbAAoKPw5wHwCaAQAbAAoKPw5wHwCaAQAAAA==.Thallenia:BAAANQADCggIGwAAAA==.Thalpura:BAAANQADCgYIBwAAAA==.Thalron:BAAANQAECgYICwAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCgYICgAAAA==.Thriller:BAAANQAECgUIBQABNQAECgoKJwAHAOcaAA==.',
Ti='Tikeidari:BAABNQAECn87AAIMAAoK/SMsAAA0AwAMAAoK/SMsAAA0AwAAAA==.Tiltedtroll:BAABNQAECn8hAAIRAAcK+Qm8LQAHAQARAAcK+Qm8LQAHAQAAAA==.',
To='Tonofcron:BAAANQADCgcIFAAAAA==.Totemeri:BAABNQAECn8nAAMQAAkKCxAieACjAQAQAAkKCxAieACjAQARAAYKlQ1YowBPAQAAAA==.Toytrux:BAAANQAECgIIAQAAAA==.',
Tr='Trappydk:BAABNQAECn8XAAIPAAoKJhl9LgB3AgAPAAoKJhl9LgB3AgAAAA==.Trappydruid:BAAANQAECgQIBQABNQAECgoKFwAPACYZAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQADCggIDgAAAA==.',
Ug='Uglyplug:BAAANQAECgUIBgAAAA==.',
Un='Unagi:BAABNQAECn8VAAIbAAYKSw8qtgCYAQAbAAYKSw8qtgCYAQAAAA==.',
Va='Vak:BAAANQAECgYICQAAAA==.Vaks:BAAANQAECgYIDwAAAA==.Valezeal:BAAANQAECgMICQAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8bAAMQAAkKdhSQdgCoAQAQAAYK7xaQdgCoAQARAAUKzhPSxgAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYJBgAAAA==.Venan:BAAANQAECgQIDAAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgIIAgAAAA==.Venev:BAAANQAECgUICgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAABNQAECn8XAAIGAAoKFA6kLQB3AQAGAAoKFA6kLQB3AQABNQAECgoKVwATAHEbAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8fAAIeAAgK2RI0PgDTAQAeAAgK2RI0PgDTAQAAAA==.',
Wa='Wanji:BAABNQAECn8hAAIPAAYKaAatJQDQAAAPAAYKaAatJQDQAAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGwAQAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgcIEwAAAA==.',
Xa='Xaharst:BAABNQAECn8jAAIUAAcKJBF0LADDAAAUAAcKJBF0LADDAAAAAA==.Xandris:BAAANQAECgUICQAAAA==.Xaya:BAABNQAECn8mAAIVAAoKwA+PIABtAQAVAAoKwA+PIABtAQAAAA==.',
Xe='Xenophorge:BAAANQAECgUICgAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgYIDQAAAA==.',
Xt='Xtayse:BAABNQAECn8jAAICAAoKJBx5AwB5AQACAAoKJBx5AwB5AQAAAA==.',
Yi='Yirya:BAABNQAECn8lAAMSAAgKew06MQCQAQASAAgKew06MQCQAQATAAEK2gHkvwAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn8mAAIJAAkK0yILAgBQAgAJAAkK0yILAgBQAgAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBAAAAA==.',
Za='Zahel:BAABNQAECn81AAIGAAkKhyFyFgDMAQAGAAkKhyFyFgDMAQAAAA==.Zandruu:BAAANQADCgUIBQABNQAECgIIBAABAAAAAA==.Zavier:BAABNQAECn8aAAMDAAkKqBavEgB2AQAlAAkK0RU8eQAsAgADAAUKfhivEgB2AQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAAANQAECgYIDgAAAA==.',
Zh='Zhee:BAAANQAECgcIDQAAAA==.',
Zo='Zobi:BAAANQADCgYIEgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.',
Zy='Zyde:BAAANQADCgQIBAAAAA==.',
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
