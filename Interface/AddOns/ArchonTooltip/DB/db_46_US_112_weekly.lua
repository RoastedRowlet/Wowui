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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Evoker-Devastation','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Demonology','Paladin-Retribution','Mage-Frost','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Paladin-Protection','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Paladin-Holy','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Havoc','Druid-Guardian','Rogue-Assassination','Warrior-Arms','Evoker-Preservation','Monk-Mistweaver',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-05-16',data={Ae='Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJBgABAAAAAA==.',
Al='Alderan:BAABLgAECn8eAAICAAcJ3AynMwArAQACAAcJ3AynMwArAQAAAA==.Aleinas:BAABLgAECn8iAAMDAAYJDhXxNQBlAQADAAYJDhXxNQBlAQAEAAQJQQgcegCFAAAAAA==.Alektophobia:BAAALgAECgcJDAAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgAECgEJAQAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.',
Am='Amorina:BAAALgAECggJEwAAAA==.',
An='Anda:BAAALgADCgYJBgAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAABLgAECn8UAAIFAAYJhAm7DQDrAAAFAAYJhAm7DQDrAAAAAA==.Andromeda:BAAALgAECgYJDQAAAA==.Aner:BAAALgAECgEJBQAAAA==.Angrygnome:BAABLgAECn8dAAIGAAkJVyAsAgBeAgAGAAkJVyAsAgBeAgAAAA==.Angélique:BAAALgAECgYJDQABLgAFFAQJCwAHANkiAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8YAAIIAAYJBSL5DQC7AQAIAAYJBSL5DQC7AQAAAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Astolvik:BAAALgAECgQJBgAAAA==.',
At='Attachedplag:BAAALgAECgYJEAAAAA==.Atulwa:BAABLgAECn8ZAAIJAAgJnRdxLgChAQAJAAgJnRdxLgChAQAAAA==.',
Au='Aurinox:BAAALgAECgUJBgAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8xAAIKAAgJExv0EAD1AQAKAAgJExv0EAD1AQAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgAECgQJCQAAAA==.Basz:BAABLgAECn8aAAIHAAYJOhhSaQBJAQAHAAYJOhhSaQBJAQAAAA==.',
Be='Beginagain:BAAALgADCgcJCQAAAA==.Belgran:BAABLgAECn8WAAILAAkJUxrSAwA9AgALAAkJUxrSAwA9AgAAAA==.Berunma:BAABLgAECn8XAAIMAAgJ2BC1TgBbAQAMAAgJ2BC1TgBbAQAAAA==.',
Bh='Bhain:BAABLgAECn8hAAMNAAcJ2h3lSgDpAQANAAcJ2h3lSgDpAQAGAAEJaA2FdAAwAAABLgAFFAMJBgAOAIMQAA==.',
Bi='Bileshots:BAAALgAECgcJCQAAAA==.Biowolf:BAACLgAFFH8NAAIPAAQJ1AYTSQAgAQAPAAQJ1AYTSQAgAQAuAAQKfyUAAg8ACAl9FVdPAKsBAA8ACAl9FVdPAKsBAAAA.Birdhunter:BAAALgAECggJEgAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAABLgAECn8aAAINAAcJ0gYsgQD5AAANAAcJ0gYsgQD5AAAAAA==.',
Bj='Bjoren:BAABLgAECn8mAAIQAAgJJyQDBAANAwAQAAgJJyQDBAANAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Bloodcaptain:BAABLgAECn8cAAMGAAkJOhf8AwD8AQAGAAkJZRb8AwD8AQARAAYJshf6CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Bootiebang:BAABLgAECn8VAAISAAYJCQNcLwDCAAASAAYJCQNcLwDCAAAAAA==.Bootycaall:BAAALgADCgkJGQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgAECgEJAQAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgEJAQAAAA==.Bucknekkid:BAAALgAECgYJCgAAAA==.Buckwhild:BAABLgAECn8VAAIQAAcJoyGQCACYAgAQAAcJoyGQCACYAgAAAA==.Burrhus:BAAALgADCgQJAgAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn8uAAMTAAgJ2iChAwCJAgATAAgJ2iChAwCJAgAOAAEJkAP5VwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8fAAMUAAYJHB/TIgB5AQAVAAYJ1BzoDQDeAQAUAAYJ5xvTIgB5AQAAAA==.Carebearr:BAAALgADCgQJBAAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJDQANAGQlAA==.Cesàrè:BAAALgAECgYJEAAAAA==.',
Ch='Chahra:BAAALgAECgYJEQAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAAALgAFFAEJAQAAAA==.Cheesecake:BAACLgAFFH8LAAIHAAQJ2SLVGACQAQAHAAQJ2SLVGACQAQAuAAQKfyAAAwcACQlfJcQCAK4DAAcACQlfJcQCAK4DAAsAAQkAAA8oAAAAAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgMJBAAAAA==.Chuubak:BAAALgAECgkJBQAAAA==.',
Cl='Clangedin:BAAALgAECgYJEAAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECggJHQANAJ4cAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreypala:BAAALgAECgIJBAAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgcJFwAAAA==.Corsten:BAAALgAECgYJEAAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgAECgQJBAAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgYJEAAAAA==.Crowmatic:BAABLgAECn8YAAIHAAgJJR9ZJQAnAgAHAAgJJR9ZJQAnAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cute:BAABLgAFFH8GAAICAAMJ+R2oGQAQAQACAAMJ+R2oGQAQAQAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMTAAkJThrbBQBCAgATAAkJThrbBQBCAgAOAAIJcBi7DAF9AAAAAA==.Dalune:BAABLgAECn8XAAIUAAYJAAidRQDEAAAUAAYJAAidRQDEAAAAAA==.Daneaus:BAABLgAECn8cAAIEAAgJPyGTCQDkAgAEAAgJPyGTCQDkAgAAAA==.Daniellson:BAABLgAECn8YAAQWAAgJKBHrLwC1AQAWAAgJKBHrLwC1AQAXAAEJPhCsSAA8AAAMAAEJAABa3AAXAAABLgAFFAUJDwAYAIEjAA==.Daredevil:BAAALgAECgYJBgABLgAECggJFwAHALUcAA==.Darkchronos:BAAALgADCgcJEAAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAABLgAECn8jAAMHAAgJVwn9bABBAQAHAAgJEAn9bABBAQAZAAgJlwWfIwDgAAAAAA==.Darnuus:BAAALgAECgQJCwABLgAECgYJDAABAAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAABLgAECn8UAAMEAAkJdQKKhgBmAAAEAAgJywGKhgBmAAADAAYJ1QAgXQBMAAAAAA==.Deathnelf:BAAALgAECgYJEgAAAA==.Deazraelle:BAAALgAECgYJEQAAAA==.Decimator:BAAALgADCggJHAAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8bAAMDAAgJKwQbOQDVAAADAAgJKwQbOQDVAAAaAAEJBAHiOwAKAAAAAA==.Dellin:BAABLgAECn8cAAIDAAgJrhSOIgBZAQADAAgJrhSOIgBZAQAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJFgAbAJwcAA==.Demonch:BAAALgAECgUJCAAAAA==.Depeche:BAABLgAECn8VAAIcAAYJiA8WdwDfAAAcAAYJiA8WdwDfAAAAAA==.Deralle:BAAALgAECgYJDAAAAA==.',
Di='Diminuendo:BAAALgAECgUJCAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAAALgAECggJEwAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgAECgQJBAAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8XAAMdAAgJPhDdFwC7AQAdAAgJPhDdFwC7AQAQAAEJ2w77ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAFFAIJAgAAAA==.Dryconias:BAACLgAFFH8FAAIOAAMJ3w1+QQDoAAAOAAMJ3w1+QQDoAAAuAAQKfyYAAg4ACQkZGzofAEgCAA4ACQkZGzofAEgCAAAA.Drèadpriest:BAABLgAECn8VAAQdAAUJwR34GACxAQAdAAUJux34GACxAQAQAAUJ0hQoMwDxAAAeAAIJCRMGUQCJAAAAAA==.Drôgô:BAABLgAECn8VAAIMAAYJnhM7TgB+AQAMAAYJnhM7TgB+AQAAAA==.',
Du='Dunkelzhan:BAABLgAECn83AAIPAAkJxhm+HwBkAgAPAAkJxhm+HwBkAgAAAA==.Duntack:BAAALgADCgEJAQAAAA==.',
Dy='Dyana:BAAALgAECggJEwAAAA==.',
Dz='Dz:BAABLgAECn81AAIbAAkJpCVeAADGAwAbAAkJpCVeAADGAwAAAA==.',
['Dø']='Dømimømmÿ:BAAALgAECgUJCAAAAA==.',
Ed='Edgyname:BAAALgAECgUJDAAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8bAAIFAAgJAAmsCQBAAQAFAAgJAAmsCQBAAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellinor:BAAALgADCgYJGAAAAA==.Elvy:BAABLgAECn8iAAIDAAgJeRWjJQDQAQADAAgJeRWjJQDQAQAAAA==.',
En='Enngin:BAAALgAECgkJEAAAAA==.',
Er='Erebus:BAAALgAECgYJDAAAAA==.Erythra:BAAALgADCgMJAwAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Ey='Eyedoc:BAAALgADCgQJBAAAAA==.',
Fa='Fabulousness:BAABLgAECn8aAAIQAAcJVx/bCwBdAgAQAAcJVx/bCwBdAgAAAA==.',
Fi='Fifefrost:BAAALgADCgMJAwAAAA==.Fishingsucks:BAAALgAECgEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgEJAQAAAA==.',
Fo='Foxx:BAAALgAECgUJDQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUQcaYAAwAQACAAYJUQcaYAAwAQAAAA==.Frostybolt:BAAALgAECgEJAgAAAA==.',
Fu='Furryriver:BAAALgAECgUJCAAAAA==.',
Ga='Galadhras:BAAALgADCgYJDgAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAAALgAECgcJEQAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn80AAMNAAgJeRX0OwCsAQANAAgJeRX0OwCsAQAGAAQJtghyRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAAALgAECgYJDgAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.Gitpull:BAAALgADCgUJBQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnimsh:BAAALgAECgEJAQAAAA==.Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Greengoatlin:BAAALgADCgcJBwAAAA==.Gremz:BAABLgAECn8mAAIfAAkJCQr0CgBYAQAfAAkJCQr0CgBYAQAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAABLgAECn8pAAIHAAkJPBzQFACKAgAHAAkJPBzQFACKAgAAAA==.',
Gu='Gumboslice:BAABLgAECn8bAAIEAAkJuRnmDQCpAgAEAAkJuRnmDQCpAgAAAA==.Gusgus:BAAALgAECgUJCAAAAA==.',
['Gä']='Gändälf:BAABLgAECn8WAAIgAAcJRxckBACAAQAgAAcJRxckBACAAQAAAA==.',
Ha='Habanero:BAABLgAECn8aAAMJAAgJHQzkQwA6AQAJAAgJHQzkQwA6AQAUAAMJ7Bt4QADYAAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgEJAgAAAA==.Hallia:BAABLgAECn8yAAIEAAkJvRVOGAA7AgAEAAkJvRVOGAA7AgAAAA==.Hark:BAAALgADCgYJFAAAAA==.Hawgwild:BAAALgAECgQJDwAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healvisprsly:BAAALgAECgcJEwAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgMJBwABAAAAAA==.Helena:BAABLgAECn83AAMTAAkJNR+3AgCwAgATAAkJUB63AgCwAgAOAAkJ1R4dEwCVAgAAAA==.Heliarc:BAAALgADCgYJGAAAAA==.',
Hi='Highfive:BAAALgAECgUJCgAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAECgYJCQAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgYJDwAAAA==.Illustriâ:BAAALgADCgYJCQABLgADCgYJDwABAAAAAA==.',
In='Insidious:BAABLgAECn8fAAIZAAkJFRrFCAA9AgAZAAkJFRrFCAA9AgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgAECgIJAgAAAA==.',
It='Itchyfeet:BAAALgAECgQJBAABLgAFFAQJCAAPAMMdAA==.Itchymage:BAACLgAFFH8IAAIPAAQJwx3GIwByAQAPAAQJwx3GIwByAQAuAAQKfyAAAg8ACAl4JDMdAAEDAA8ACAl4JDMdAAEDAAAA.',
Ja='Jacckiemoon:BAAALgAECgMJAwABLgAECgcJEwABAAAAAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgAECgUJBQAAAA==.',
Ji='Jigs:BAABLgAECn8pAAIMAAgJMxTCLgDQAQAMAAgJMxTCLgDQAQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECgYJDAABAAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kabøchi:BAAALgAECgUJBQAAAA==.Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgAECgIJAgAAAA==.Kamstareater:BAABLgAECn8WAAIcAAgJ0BFUSABeAQAcAAgJ0BFUSABeAQAAAA==.Kanakas:BAAALgAECgcJEQAAAA==.Kanaloa:BAABLgAECn8bAAIPAAcJfgeGlQAUAQAPAAcJfgeGlQAUAQAAAA==.Kayler:BAAALgAECgYJBgAAAA==.',
Ke='Kegerator:BAAALgAECgEJAQAAAA==.Keirin:BAAALgAECggJEgAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgAECgMJAwAAAA==.Kenshan:BAAALgADCgcJCgAAAA==.Kevinbox:BAAALgAECgYJDQAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8VAAIcAAgJYRENPwB/AQAcAAgJYRENPwB/AQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8VAAIbAAcJsA9nLQBZAQAbAAcJsA9nLQBZAQAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJFAAAAA==.',
Ki='Kickazdin:BAAALgAFFAEJAQAAAA==.Kiryie:BAAALgAECgYJEQAAAA==.Kisäme:BAAALgAECgEJAQAAAA==.',
Kl='Klad:BAAALgADCgYJBgAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8hAAIhAAcJ4xu8DwDGAQAhAAcJ4xu8DwDGAQAAAA==.Krinack:BAABLgAECn8cAAISAAgJ6xGbFACnAQASAAgJ6xGbFACnAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ks='Kshamify:BAAALgAECgEJAQAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.Kutiel:BAAALgAECgEJAQAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgYJEAAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAAALgAECgcJEQAAAA==.Lailyre:BAAALgAECgYJBQABLgAECgYJBgABAAAAAA==.Lassan:BAAALgAECgYJCQAAAA==.Later:BAAALgAECgcJBwAAAA==.Latimir:BAAALgAECgIJAgAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8eAAIDAAgJ6g/7IwBPAQADAAgJ6g/7IwBPAQAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgYJCQABAAAAAA==.',
Lb='Lb:BAAALgADCgEJAQABLgAECggJCQABAAAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8IAAIUAAMJmwqHIgDFAAAUAAMJmwqHIgDFAAAuAAQKfyYAAhQACQknFiQdACgCABQACQknFiQdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8WAAMQAAUJ5B/CMwBwAQAQAAUJ5B/CMwBwAQAeAAQJDBHTQQCvAAAAAA==.Lightningfox:BAABLgAECn8UAAMOAAYJeRn/XQBrAQAOAAYJeRn/XQBrAQAbAAIJug5+WwBpAAAAAA==.Lightsfallen:BAAALgAECgcJBwAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAAALgAECgYJEQAAAA==.Littlemo:BAAALgAECgUJCAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgUJCAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8cAAINAAgJXBk8MADYAQANAAgJXBk8MADYAQAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJKgAXAJsOAA==.Luckystop:BAAALgAECgUJCAAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.Luraris:BAAALgADCgMJAwAAAA==.',
Ly='Lyrska:BAABLgAECn8bAAIXAAYJaBFBIABJAQAXAAYJaBFBIABJAQAAAA==.Lytearrow:BAABLgAECn8bAAIMAAcJdA/hVQBHAQAMAAcJdA/hVQBHAQAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJCgAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAAALgAECggJEgAAAA==.Maleficents:BAABLgAECn8gAAIDAAYJiQ/6MQD5AAADAAYJiQ/6MQD5AAAAAA==.Malurius:BAAALgAECgcJEwAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8hAAMEAAcJXB/AIQD0AQAEAAYJYx7AIQD0AQAaAAcJ6Ro+CQDUAQAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECgcJIQAEAFwfAA==.Mannypack:BAAALgAECggJEwAAAA==.Maranelli:BAAALgADCgYJBgAAAA==.Maseles:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Maxiticon:BAAALgADCgUJBQAAAA==.',
Mc='Mcdawg:BAAALgADCgQJBAAAAA==.Mcleary:BAAALgAECgQJBAAAAA==.',
Me='Melinashala:BAABLgAECn8cAAINAAgJFgPdlADTAAANAAgJFgPdlADTAAAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgQJCQAAAA==.Metide:BAAALgAECgQJBAAAAA==.',
Mi='Miala:BAAALgADCgYJBgAAAA==.Miler:BAAALgAECgQJBgAAAA==.Minisor:BAAALgAECgUJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8XAAIEAAcJqyG0EACIAgAEAAcJqyG0EACIAgAAAA==.Mogryn:BAAALgAECgYJBgAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Moll:BAAALgADCgEJAQAAAA==.Mommybree:BAAALgAECgQJBAAAAA==.Monksterz:BAABLgAECn8mAAIKAAgJQyFABwCOAgAKAAgJQyFABwCOAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Moonwarriorx:BAAALgAECgQJBAAAAA==.Morsecode:BAABLgAECn8VAAIGAAcJ/xJbCQBgAQAGAAcJ/xJbCQBgAQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8hAAINAAcJ2xR6TAB2AQANAAcJ2xR6TAB2AQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAAALgAECggJEgAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDgABLgAECgEJAQABAAAAAA==.Muldern:BAAALgADCgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Mustachekick:BAAALgADCgIJAgAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAABLgAECn8ZAAIJAAYJlg3qTQASAQAJAAYJlg3qTQASAQAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8MAAIFAAQJ2iVSAADHAQAFAAQJ2iVSAADHAQAuAAQKfzsAAgUACQn+JScAAHgDAAUACQn+JScAAHgDAAAA.Nafir:BAAALgADCgYJEQAAAA==.Narlin:BAAALgAECgIJAwAAAA==.Nasta:BAAALgAECgQJBQAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCAAAAA==.Nazgor:BAAALgAECgMJAwAAAA==.',
Ne='Neckromancy:BAAALgADCgcJBwAAAA==.Necrosius:BAAALgAECgQJBwAAAA==.Neonarc:BAEALgADCgYJEQAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgADCgkJEgAAAA==.Nightsbane:BAAALgADCgcJCgAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAAALgAECgEJAgAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8VAAIcAAcJRgXAiAC6AAAcAAcJRgXAiAC6AAAAAA==.',
Ob='Obscyra:BAAALgADCgYJCwAAAA==.',
Ol='Olmek:BAACLgAFFH8RAAICAAYJnBEACgBoAQACAAYJnBEACgBoAQAuAAQKfxwAAgIABwkrJgUJAI0CAAIABwkrJgUJAI0CAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgQJBQABLgAECgcJEwABAAAAAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgYJBgAAAA==.Pallytune:BAABLgAECn8aAAIbAAkJ8Q6QGQDsAQAbAAkJ8Q6QGQDsAQAAAA==.Pandalorian:BAAALgAECgYJEAAAAA==.Pandamajack:BAAALgAECgcJCQAAAA==.',
Ph='Philandre:BAAALgAECgQJBgAAAA==.',
Pi='Picoso:BAABLgAECn8XAAIPAAcJuwffkQAaAQAPAAcJuwffkQAaAQAAAA==.Piianca:BAAALgADCgcJBwAAAA==.Piianna:BAABLgAECn8YAAIQAAYJrBu9GAC8AQAQAAYJrBu9GAC8AQAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJCQAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgEJAQAAAA==.Putrigord:BAAALgAECgQJCwAAAA==.',
Qi='Qik:BAAALgADCgcJBwAAAA==.Qikkaw:BAABLgAECn8YAAMJAAYJSRIsTAAaAQAJAAYJSRIsTAAaAQAUAAUJtwk1TgClAAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8YAAIiAAgJ0hHSFgAgAQAiAAgJ0hHSFgAgAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAAALgAECggJEAAAAA==.Raganar:BAABLgAECn8XAAITAAYJDxQ8FwASAQATAAYJDxQ8FwASAQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgYJGAAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAAALgAECggJEwAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAAALgAECgcJCgAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAABLgAECn8XAAIJAAYJJR7HHwD5AQAJAAYJJR7HHwD5AQAAAA==.',
Ri='Rikershipdwn:BAAALgAECggJEwAAAA==.Rikersline:BAAALgADCgkJCQAAAA==.Rimish:BAAALgAECgcJCQABLgAECgkJHwAjAHIYAA==.Rimrave:BAABLgAECn8cAAQIAAgJQRvUEACLAQACAAYJIxscNQDVAQAIAAYJiB3UEACLAQAkAAYJhw2FIwDpAAAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgYJGAAAAA==.Rivik:BAAALgAECgQJAwAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8qAAMXAAgJmw6KFgCkAQAXAAgJmw6KFgCkAQAMAAEJAADX1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIXAAYJUxTNFgBdAQAXAAYJUxTNFgBdAQAAAA==.Rokte:BAAALgAECgYJEQAAAA==.Roo:BAAALgAECgEJAgAAAA==.Rook:BAABLgAECn8YAAQNAAcJhh/OPACpAQANAAcJRh3OPACpAQAGAAMJmBlrGwCPAAARAAEJAABuLAAAAAAAAA==.Rosekenway:BAAALgAECgYJDgABLgAECggJKgAXAJsOAA==.',
Rr='Rratt:BAAALgAECgQJBAAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgADCgUJCQAAAA==.Running:BAAALgAECgIJAgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMMAAYJaA+qZQA2AQAMAAYJaA+qZQA2AQAWAAEJwQPplAAlAAAAAA==.Saintotem:BAAALgAECggJEAAAAA==.Samartyr:BAAALgAECgUJCAAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sangwynaris:BAAALgADCgYJCQAAAA==.Saphiiraa:BAABLgAECn8WAAIlAAgJiQtWEQBqAQAlAAgJiQtWEQBqAQAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAABLgAECn8YAAIPAAYJ2hSKeABJAQAPAAYJ2hSKeABJAQAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIWAAcJpgzuDwATAQAWAAcJpgzuDwATAQAAAA==.',
Se='Sedrick:BAABLgAECn8sAAMbAAkJsh9vCADAAgAbAAgJjCBvCADAAgAOAAYJehXCYwBdAQAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgYJCQABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgYJCQABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgYJCQABAAAAAA==.Sekzen:BAAALgAECgYJCQAAAA==.Semiazas:BAABLgAECn8kAAQRAAgJAQ/rBwCCAQARAAgJAQ/rBwCCAQANAAUJ2QmotwDpAAAGAAEJAAD7egAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgAECgQJBAAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shattered:BAAALgAECgUJBgAAAA==.Shayrisa:BAABLgAECn8sAAMJAAkJxBGDKgC4AQAJAAkJxBGDKgC4AQAUAAcJ4w54MgAZAQAAAA==.Shazool:BAAALgAECgYJEQABLgAECgkJMgAEAL0VAA==.Sheep:BAABLgAECn8UAAIPAAYJeBUKfABDAQAPAAYJeBUKfABDAQAAAA==.Shifterz:BAAALgAECgUJBwAAAA==.Shrieke:BAAALgAECgQJBAAAAA==.Shrubbery:BAAALgAECggJEwAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgAECgEJAQABLgAECggJGgAiAAMPAA==.Sindella:BAAALgADCgIJAgABLgAECggJGgAiAAMPAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8aAAMiAAgJAw9CGAARAQAiAAYJhBNCGAARAQAaAAMJ8AVoJgBpAAAAAA==.',
Sk='Skedaddle:BAAALgAECgUJCQAAAA==.Skithíryx:BAAALgAECgUJBwABLgAECgYJCwABAAAAAA==.',
Sl='Slashbndcoot:BAAALgAECgEJAQAAAA==.Slashgquit:BAACLgAFFH8OAAIZAAQJlB4SCABxAQAZAAQJlB4SCABxAQAuAAQKfzEAAhkACAlVJa0DAMkCABkACAlVJa0DAMkCAAAA.Slumbermist:BAABLgAECn8nAAMYAAkJrBCNFgCvAQAYAAkJrBCNFgCvAQAmAAYJihKrLQBLAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8dAAMTAAcJrBrODACfAQATAAcJrBrODACfAQAbAAUJqRAnPAAEAQAAAA==.Soras:BAAALgADCgYJFQAAAA==.',
St='Steph:BAAALgADCgYJDAAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAAALgAECgcJEQAAAA==.',
Sz='Szasstaam:BAABLgAECn8WAAIgAAgJRwdVBgAYAQAgAAgJRwdVBgAYAQAAAA==.',
['Sé']='Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAINAAcJ9wkVcQAcAQANAAcJ9wkVcQAcAQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAABLgAECn8UAAIPAAYJ1B/ebgD2AQAPAAYJ1B/ebgD2AQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAAALgAECgcJEQAAAA==.',
Ti='Tiger:BAACLgAFFH8xAAMaAAkJECUBAACwAwAaAAkJECUBAACwAwAEAAMJxhYuFwCoAAAuAAQKfyoAAxoACQnqJgUAABYEABoACQnqJgUAABYEAAQAAQm1C4TEAD8AAAAA.Tinnea:BAAALgAECgUJDgAAAA==.Titanosaurus:BAAALgAECgUJCAAAAA==.Tizzly:BAABLgAECn8rAAIPAAkJzQ65SQC7AQAPAAkJzQ65SQC7AQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAAALgAECgYJEQAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAAALgAECgcJEQAAAA==.Troagstar:BAABLgAECn8XAAIUAAcJJhPSKABRAQAUAAcJJhPSKABRAQAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJFAAAAA==.',
Ty='Tyraana:BAABLgAECn8xAAMhAAgJiB4fDgDfAQAhAAgJiB4fDgDfAQAcAAgJ3BQcNgCiAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAAALgAECgcJEQAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Us='Ushas:BAABLgAECn8mAAIQAAkJCxfaFQDZAQAQAAkJCxfaFQDZAQAAAA==.',
Va='Vali:BAABLgAECn8hAAIWAAcJLR+yBQD/AQAWAAcJLR+yBQD/AQAAAA==.Valindrea:BAAALgAECgUJCAAAAA==.Vasrael:BAABLgAECn8hAAMbAAcJYRzHEwAmAgAbAAcJYRzHEwAmAgAOAAQJsBB5nQDvAAAAAA==.Vav:BAABLgAECn8UAAMMAAYJeBfdbAALAQAMAAYJeBfdbAALAQAXAAIJswzwRwA9AAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgIJAgAAAA==.',
Vi='Vithper:BAAALgAECgcJDAAAAA==.',
Vn='Vnia:BAAALgADCgMJAwAAAA==.',
Vo='Voidmuffinz:BAACLgAFFH8GAAIcAAMJ4gwMQwDTAAAcAAMJ4gwMQwDTAAAuAAQKfx8AAhwACQnYF/wjAPgBABwACQnYF/wjAPgBAAAA.',
Vy='Vynis:BAAALgAECgcJDQABLgAECgkJGgAbAPEOAA==.Vyrahildard:BAABLgAECn8cAAIOAAgJdRl6QAC8AQAOAAgJdRl6QAC8AQAAAA==.',
Wa='Wakkiq:BAAALgADCgkJCQAAAA==.Waringoutlaw:BAAALgADCgkJCQAAAA==.Wasteland:BAABLgAECn8nAAIZAAkJmhH9EAClAQAZAAkJmhH9EAClAQAAAA==.',
We='Weaselhunter:BAAALgAECgUJBQABLgAECgcJEwABAAAAAA==.Weasellock:BAAALgAECgcJEwAAAA==.Weaselmage:BAAALgAECgYJDAABLgAECgcJEwABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECgIJAgAAAA==.',
Wi='Wildweasel:BAAALgAECgQJBQABLgAECgcJEwABAAAAAA==.Winterhide:BAABLgAECn8hAAIHAAcJ/xR1VAB/AQAHAAcJ/xR1VAB/AQAAAA==.',
Xa='Xallie:BAEBLgAECn80AAIcAAkJgxfMHQAdAgAcAAkJgxfMHQAdAgAAAA==.Xanvyr:BAABLgAECn8hAAIOAAkJXhlJIwAyAgAOAAkJXhlJIwAyAgAAAA==.Xaquillis:BAACLgAFFH8HAAMHAAMJuQ2uawDeAAAHAAMJuQ2uawDeAAALAAEJqwUVEgBCAAAuAAQKfyIAAwcACAmVGyc8AEcCAAcACAmVGyc8AEcCAAsAAQnZDvAiAC8AAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAMJBwAHALkNAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8cAAIfAAgJ2SItAgCiAgAfAAgJ2SItAgCiAgAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJHwAUABwfAA==.',
Ya='Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zaden:BAAALgADCgUJBQAAAA==.Zarihanna:BAABLgAECn8tAAIPAAgJ+hOHWACSAQAPAAgJ+hOHWACSAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8XAAINAAgJ2AanbgAhAQANAAgJ2AanbgAhAQAAAA==.Zenshi:BAAALgAECgEJAQAAAA==.Zeperios:BAAALgAECgYJCgAAAA==.Zeril:BAABLgAECn8UAAMRAAgJjhdJBgCwAQARAAgJjhdJBgCwAQANAAEJHgUZDwEpAAAAAA==.Zestull:BAABLgAECn8hAAIKAAcJbSQZCQBrAgAKAAcJbSQZCQBrAgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgQJBAAAAA==.',
Zo='Zorc:BAACLgAFFH8JAAIUAAQJmxMnEgAyAQAUAAQJmxMnEgAyAQAuAAQKfycAAhQACQmKIPsJAPQCABQACQmKIPsJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJBAAAAA==.',
Zy='Zyate:BAABLgAECn8xAAINAAkJTBKHLgDgAQANAAkJTBKHLgDgAQAAAA==.Zyrryn:BAABLgAECn8XAAIFAAgJwQNHDQDzAAAFAAgJwQNHDQDzAAAAAA==.',
['Ät']='Ätlas:BAAALgADCgYJDAAAAA==.',
['Ër']='Ërëbus:BAAALgADCgQJBAAAAA==.',
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
