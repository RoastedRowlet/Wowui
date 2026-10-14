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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Warlock-Demonology','Paladin-Holy','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Warlock-Destruction','Druid-Guardian','Druid-Feral','DeathKnight-Blood','Paladin-Protection','Warrior-Protection','Hunter-BeastMastery','Monk-Windwalker','Druid-Restoration','Shaman-Elemental','Priest-Discipline','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Monk-Brewmaster','Warrior-Fury','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQADCgYIBgAAAA==.',
Ae='Aenimal:BAAANQAECgQIBAAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECgkJKAABAPkQAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.',
Am='Amberlie:BAAANQAECggICQAAAA==.Aminni:BAABNQAECn8cAAICAAgKVxGrZADcAQACAAgKVxGrZADcAQAAAA==.Amorgal:BAAANQADCgUICQAAAA==.Amorir:BAABNQAECn8YAAIDAAkKxQ70kAD+AQADAAkKxQ70kAD+AQAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAABNQAECn8bAAIEAAgKlQ5nSADEAQAEAAgKlQ5nSADEAQAAAA==.Andeddo:BAABNQAECn8uAAMFAAkKOx2YGQDyAgAFAAkKOx2YGQDyAgAGAAgKHBRuPgDLAQAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAABNQAECn8XAAIEAAkKqBtkGwDrAgAEAAkKqBtkGwDrAgAAAA==.Ariodecay:BAAANQAFFAEIBAAAAA==.Ariodh:BAACNQAFFH8RAAIHAAUKyiVtBAAhAgAHAAUKyiVtBAAhAgA1AAQKfysAAgcACQp0JoUCAMwDAAcACQp0JoUCAMwDAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBAAAAA==.Arnak:BAAANQADCgMJAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8OAAIIAAQKABPYGQArAQAIAAQKABPYGQArAQA1AAQKfywAAggACQoCHrlAAI0CAAgACQoCHrlAAI0CAAAA.',
At='Athenà:BAAANQABCgQJBwAAAA==.Atonedaka:BAAANQAECgEIAQABNQAECggIGAAJAJwfAA==.',
Av='Avye:BAAANQAECgQIDQAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgUIBQAAAA==.Banthr:BAAANQAECgcIEgAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Benchedwin:BAAANQADCggIDgAAAA==.',
Bi='Bigcow:BAAANQAECgYJEQAAAA==.Bigdeeps:BAABNQAECn8iAAIKAAkKFyNvGwBIAwAKAAkKFyNvGwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn8bAAIBAAgKmB/7IwDaAgABAAgKmB/7IwDaAgAAAA==.Blastcannon:BAABNQAECn8gAAMLAAgKowO0HQD8AAALAAcK1wO0HQD8AAAMAAQK5QGHqwFiAAAAAA==.Bluejuly:BAAANQABCgQJBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECgkJNQANAJYfAA==.',
Br='Bravehearth:BAAANQADCgYIBgABNQADCgUIBQAOAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8gAAIEAAgKVRLoPwD4AQAEAAgKVRLoPwD4AQAAAA==.Bulan:BAABNQAECn8iAAIPAAgKQCQHBgA5AwAPAAgKQCQHBgA5AwAAAA==.',
Ca='Candypants:BAABNQAECn8gAAIPAAcKahuPFQAfAgAPAAcKahuPFQAfAgAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECn8lAAILAAgK8yBwAwAOAwALAAgK8yBwAwAOAwAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAAANQAECgUICQAAAA==.Cayssaris:BAAANQAECgQIDQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn8nAAMQAAgKVh5xBAC/AgAQAAgK5B1xBAC/AgARAAYKNRsFGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgEIAQABNQAECggIEAAOAAAAAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chappedlips:BAAANQAECgEIAQAAAA==.Cheetor:BAAANQAECgIIAgABNQAECgkJNgASAPgfAA==.Chidaka:BAAANQAECgEIAgABNQAECggIGAAJAJwfAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAABNQAECn8dAAMIAAkKeRTSfQDnAQAIAAcKGxnSfQDnAQATAAUKgQ1wNwDiAAAAAA==.Cosairi:BAABNQAECn8YAAICAAcKfhGEgQCEAQACAAcKfhGEgQCEAQAAAA==.Cougztroll:BAABNQAECn8XAAMUAAkKuxH2HQCqAQAUAAgKRhH2HQCqAQAVAAEKeBSPPQA9AAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8UAAINAAgK3CBvDQCTAgANAAgK3CBvDQCTAgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECggIJwAQAFYeAA==.',
Cu='Cuttercupx:BAAANQAECgUICgABNQAECgcIDQAOAAAAAA==.',
Da='Dakadin:BAABNQAECn8YAAIJAAgKnB8BJADZAgAJAAgKnB8BJADZAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn8tAAIDAAkKwRlrUgCaAgADAAkKwRlrUgCaAgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn8vAAIWAAcKmBF3XwBxAQAWAAcKmBF3XwBxAQAAAA==.Dashy:BAAANQAECgQIBAAAAA==.Dawnstone:BAAANQAECgQIDAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn8ZAAIIAAkKiROhXgA4AgAIAAkKiROhXgA4AgAAAA==.Deafsmash:BAAANQAECgIIBAABNQAECggIJAAFAI0gAA==.Delamyr:BAAANQABCgIJAwABNQADCgYIBgAOAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQAECgQIDAAOAAAAAA==.Destroyevsky:BAAANQAECgQICAAAAA==.Detonate:BAAANQADCgUICQAAAA==.',
Di='Digem:BAAANQABCgQJBAABNQADCgcIEwAOAAAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhlaFwDoAAADAAMKPhlaFwDoAAAXAAIKYwqZDgBYAAA1AAQKfyYAAwMACQpgI9McAE4DAAMACQpgI9McAE4DABcABAo7GZ8/APcAAAAA.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJHQAPAO4fAA==.Dragonwarior:BAABNQAECn8YAAIKAAkK6A5xoQDEAQAKAAkK6A5xoQDEAQAAAA==.Drykkr:BAAANQAECgUIEgAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggICQAOAAAAAA==.Element:BAAANQADCgUIBQAAAA==.Elpollo:BAAANQAECgQIBQAAAA==.Elvar:BAAANQADCgYIFAAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgkJIAADAKsQAA==.',
Ep='Epitome:BAABNQAECn8fAAMLAAgKBxw0CABeAgALAAgKBxw0CABeAgAMAAEKAAA0xQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.',
Et='Ethereal:BAAANQADCgIIAgAAAA==.Etude:BAAANQAECgMIBAAAAA==.',
Eu='Eunha:BAAANQAECgUIDAABNQAECggIEAAOAAAAAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgcILwAWAJgRAA==.Evergrey:BAAANQAECgQIBQAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQADCggICgAAAA==.Falasdaer:BAAANQAECgQIBgAAAA==.Falstaff:BAAANQADCgcJDgAAAA==.Fatalis:BAAANQADCggIHgAAAA==.Fatterblunt:BAACNQAFFH8OAAIEAAQKpA7PEwAnAQAEAAQKpA7PEwAnAQA1AAQKfyoAAgQACQo9G/wrAHgCAAQACQo9G/wrAHgCAAAA.',
Fe='Feldar:BAABNQAECn8hAAIDAAgKmx0JXACAAgADAAgKmx0JXACAAgAAAA==.Feronite:BAABNQAECn81AAINAAkKlh+3BgAXAwANAAkKlh+3BgAXAwAAAA==.',
Fi='Fizzleclaw:BAAANQAFFAEIAQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAFFAEIAQAOAAAAAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgQIDAAAAA==.',
Fr='Fredwin:BAAANQAECgcIEAAAAA==.Free:BAAANQADCgcIDQABNQAECgQIBAAOAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBAAOAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Ganthex:BAAANQADCgUJBQAAAA==.Gapper:BAABNQAECn82AAISAAkK+B8LCQBAAwASAAkK+B8LCQBAAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAYALwgAA==.Gargodath:BAAANQABCggIDgAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECn8cAAIZAAkKUBssKQDyAgAZAAkKUBssKQDyAgAAAA==.Glitterpants:BAAANQAECgUIBQAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8cAAIKAAgKuxNWfAAgAgAKAAgKuxNWfAAgAgAAAA==.',
Go='Gojira:BAAANQAECgQIDQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECn8dAAMPAAgKdBrGEgBNAgAPAAgKdBrGEgBNAgAaAAEKCA+7agAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIDwAOAAAAAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAAANQAECgQIDQAAAA==.',
Ha='Haerin:BAAANQAECgUICAABNQAECggIEAAOAAAAAA==.Hairydresden:BAAANQABCgIIAgAAAA==.Harnel:BAABNQAECn8aAAIDAAYKGAQaGwHrAAADAAYKGAQaGwHrAAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgQIBQAAAA==.Hellborne:BAAANQABCgIIAgABNQAECgQIBAAOAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQAOAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAECgkJNQANAJYfAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgQIBQAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAABNQAECn8XAAIMAAkKgB4NNAAiAwAMAAkKgB4NNAAiAwAAAA==.Kaliel:BAAANQADCgcIGAAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgUJBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwAIAEsRAA==.',
Ke='Kernelpanic:BAACNQAFFH8PAAQFAAQKQx/WCwBNAQAFAAQKZB7WCwBNAQAGAAIKZBn6EwCZAAAWAAEKAABlNQAnAAA1AAQKfx8AAwUACAqnId8sAH4CAAUACAqnId8sAH4CAAYAAQolFoylADsAAAAA.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYIDgAAAA==.Kirkle:BAABNQAECn8rAAITAAgK3BsVBgCtAgATAAgK3BsVBgCtAgAAAA==.',
Ko='Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYICgAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwAIAEsRAA==.Krukar:BAAANQAECgQICQAAAA==.',
Ku='Kulrath:BAAANQAECggIDAAAAA==.',
Kw='Kwovie:BAABNQAECn8bAAIUAAgKPxyREABSAgAUAAgKPxyREABSAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8YAAIDAAgKvw+XpwDMAQADAAgKvw+XpwDMAQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgQIBAABNQAECgQIDAAOAAAAAA==.Lavasaurus:BAAANQAECgQIDAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAAANQAECgYIDwAAAA==.',
Li='Lifebloomz:BAABNQAECn8ZAAMbAAgKYBEFKgDLAQAbAAgKYBEFKgDLAQAUAAEK3wEIcAAZAAAAAA==.Lilfluffcc:BAABNQAECn8dAAINAAkKtBE/EQBTAgANAAkKtBE/EQBTAgAAAA==.',
Lo='Lockward:BAABNQAECn8dAAIIAAgKLRrWUwBWAgAIAAgKLRrWUwBWAgAAAA==.Lorblor:BAABNQAECn8WAAIHAAcKPh+qLQAzAgAHAAcKPh+qLQAzAgAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8iAAIcAAgKRhhRVQAhAgAcAAgKRhhRVQAhAgAAAA==.Lunafox:BAAANQAECggIEAAAAA==.Lunamae:BAABNQAECn8aAAIMAAgKvQ0NzQDpAQAMAAgKvQ0NzQDpAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgkJLQABAEQcAA==.Luvvyyaa:BAABNQAECn8tAAMBAAkKRBzxPQBvAgABAAkKRBzxPQBvAgAdAAIKwQolIABeAAAAAA==.Luvyya:BAAANQAECgUIBgABNQAECgkJLQABAEQcAA==.',
Ly='Lythomancer:BAABNQAECn8aAAITAAcKKgfUIABpAQATAAcKKgfUIABpAQAAAA==.',
Ma='Maddeena:BAAANQAECgQIDQAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAIIAAUKSxFAEACEAQAIAAUKSxFAEACEAQA1AAQKfzEAAggACQpUIhQZACEDAAgACQpUIhQZACEDAAAA.',
Mc='Mcmercie:BAABNQAECn8YAAIXAAkKZg6BIwDCAQAXAAkKZg6BIwDCAQAAAA==.',
Me='Mechacooter:BAABNQAECn8kAAIeAAkKcRluGwCeAgAeAAkKcRluGwCeAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8hAAIMAAcKrBK13ADLAQAMAAcKrBK13ADLAQAAAA==.Melchiorr:BAABNQAECn8xAAIfAAkKqxuMAgD0AgAfAAkKqxuMAgD0AgAAAA==.Melynne:BAABNQAECn8XAAICAAkKjg4SZADeAQACAAkKjg4SZADeAQAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECggIFgADAA0jAA==.Minji:BAAANQAECgYICgABNQAECggIEAAOAAAAAA==.Minsoo:BAABNQAECn8eAAIPAAkKYR3CCwDFAgAPAAkKYR3CCwDFAgAAAA==.',
Ml='Mlrgl:BAABNQAECn8WAAMZAAkKchyXQgChAgAZAAgKqhuXQgChAgASAAUKuQ+xRQAnAQAAAA==.Mlrglo:BAAANQAECgUJBgABNQAECgkJFgAZAHIcAA==.',
Mo='Mormegil:BAAANQAECgQIDAAAAA==.Moshimoshi:BAABNQAFFH8HAAICAAIKURTVHgCVAAACAAIKURTVHgCVAAAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQAECgQIDAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECgkJJAAeAHEZAA==.',
Ne='Nessará:BAABNQAECn8lAAIBAAgK8gh5gwCIAQABAAgK8gh5gwCIAQAAAA==.',
Ni='Nightgodjuju:BAAANQAECgYIDgAAAA==.Nikna:BAAANQAECgUICwABNQAECgkJHAAZACMbAA==.',
Nu='Nudacris:BAAANQAECggIDwABNQAECgkJFgAZAHIcAA==.Nuraga:BAABNQAECn8YAAIYAAgK8yJIBQAhAwAYAAgK8yJIBQAhAwAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAABNQAECn8WAAISAAcKExbxNACiAQASAAcKExbxNACiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAABNQAECn8dAAIPAAkK7h+XBgArAwAPAAkK7h+XBgArAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECgcIEAAOAAAAAA==.Pattilicious:BAABNQAECn8UAAIDAAgK7Q3ZuwCfAQADAAgK7Q3ZuwCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8dAAMRAAgKzBgZFwDXAQARAAcKhxcZFwDXAQAgAAUKbxOALQAzAQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn8oAAMXAAkKrhFEIADfAQAXAAkKCBFEIADfAQADAAIK5gvgagFuAAAAAA==.',
Py='Pyrug:BAAANQADCgYICwABNQAECgkJGQAIAIkTAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgkJJQAZAIMPAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rannmagnison:BAABNQAECn8fAAIDAAcKcAem5QBJAQADAAcKcAem5QBJAQAAAA==.Raquoon:BAAANQAECgQICQAAAA==.Razzalghoul:BAABNQAECn8ZAAMGAAgK9hHrPQDOAQAGAAgK9hHrPQDOAQAFAAQKEQfQqAChAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECgUIEAAOAAAAAA==.Reuli:BAAANQAECgIIAwAAAA==.Reze:BAABNQAECn8eAAIaAAkKhSJSDgD4AgAaAAkKhSJSDgD4AgABNQAFFAgIIAAHAGMlAA==.',
Rh='Rhaeynera:BAAANQAECgUIEwAAAA==.',
Ri='Riezen:BAABNQAECn8bAAIFAAYKUxg8ZQB4AQAFAAYKUxg8ZQB4AQAAAA==.Rinorik:BAABNQAECn8hAAMIAAcK0x4obQATAgAIAAYKnh4obQATAgATAAIK3B9PQwC2AAAAAA==.',
Ro='Rockbiter:BAAANQADCgYIBgAAAA==.Rockhhard:BAAANQAECgIIAgAAAA==.Roeken:BAABNQAECn8eAAIKAAgKghLkjAD4AQAKAAgKghLkjAD4AQAAAA==.Rollingman:BAAANQAECgQICAAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8dAAIWAAgKmCI+FQAAAwAWAAgKmCI+FQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECn8dAAISAAcKXyPWEgDKAgASAAcKXyPWEgDKAgAAAA==.',
Sa='Samsó:BAABNQAECn8hAAMJAAgKmRWEUAAnAgAJAAgKmRWEUAAnAgADAAEKAACPnQE1AAAAAA==.Sapharina:BAABNQAECn8oAAIBAAkK+RCdUgAoAgABAAkK+RCdUgAoAgAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8dAAQVAAkKBB2OCADHAgAVAAgKRB2OCADHAgAbAAYKwBkPLAC4AQAUAAIKUg3sTgBfAAAAAA==.Schreckstoff:BAABNQAECn8eAAIcAAgKRRO5WwALAgAcAAgKRRO5WwALAgAAAA==.',
Se='Searfang:BAABNQAECn8kAAIcAAkKQRgkPgB6AgAcAAkKQRgkPgB6AgAAAA==.Sematic:BAAANQAECgMIAwABNQAFFAYIFQAKAK4dAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shamor:BAAANQADCgcIBwAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA24VACCAQAEAAcKvA24VACCAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAABNQAECn8cAAIVAAgK6xT+DgAgAgAVAAgK6xT+DgAgAgAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skëëts:BAAANQADCgUIBQAAAA==.',
Sl='Slampoof:BAAANQABCggIDAAAAA==.Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAAOAAAAAA==.Smashmaster:BAAANQAECgQIBAAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwAOAAAAAA==.',
Sn='Snowscayia:BAABNQAECn9TAAMbAAkKgSFpBgBaAwAbAAkKgSFpBgBaAwAEAAgKwxKzNQA5AgAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBxrIQDAAgAEAAkKbBxrIQDAAgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8hAAILAAcKRRwZCwAPAgALAAcKRRwZCwAPAgAAAA==.',
Sq='Squadie:BAABNQAECn8gAAIZAAgK7wpdiwDwAQAZAAgK7wpdiwDwAQAAAA==.Squanchs:BAACNQAFFH8GAAICAAIKECRFGQDMAAACAAIKECRFGQDMAAA1AAQKfygAAgIACQoVJsgDAK0DAAIACQoVJsgDAK0DAAE1AAQKBggHAA4AAAAA.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgcICAAAAA==.',
St='Story:BAAANQADCgUICwAAAA==.Styrcius:BAABNQAECn8iAAIXAAcKzhwyFgBKAgAXAAcKzhwyFgBKAgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECgcIEAAAAA==.Suniah:BAAANQAECgYIDgAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAYIFQAKAK4dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQADCgcIBwAAAA==.Süß:BAAANQADCgIIAgABNQAECgkJHQAVAAQdAA==.',
Ta='Tabius:BAAANQAECgUIEgAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.',
Te='Tealle:BAAANQABCgIIAgABNQAECgQIDAAOAAAAAA==.Teddumby:BAAANQADCgcICAABNQAECgcIDQAOAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAAANQAECgQIDQAAAA==.',
Th='Thelorìn:BAABNQAECn8bAAIUAAgK3BvzDACUAgAUAAgK3BvzDACUAgAAAA==.Thiccdiq:BAABNQAECn8hAAIhAAcKBh8fCwBaAgAhAAcKBh8fCwBaAgAAAA==.Thiccgirl:BAAANQABCgMIBAAAAA==.Thirstycow:BAAANQAECgcIEgAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECn87AAIZAAkKqyTeBwCeAwAZAAkKqyTeBwCeAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAABNQAECn8oAAIEAAkKRxv7HQDYAgAEAAkKRxv7HQDYAgAAAA==.Tråitors:BAAANQAECgYIEQAAAA==.',
Ts='Tsarevich:BAAANQAECgQIDQAAAA==.',
Tw='Twileaf:BAAANQAECgUIEgAAAA==.',
Ul='Ully:BAAANQAECgUICwAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIFAAgKIhMqWACsAQAFAAgKIhMqWACsAQAAAA==.Unug:BAAANQADCggIDgABNQAECgkJGQAIAIkTAA==.',
Ut='Uthmansur:BAAANQAECgUICwAAAA==.',
Va='Varkbyte:BAAANQAECgQIDQAAAA==.Varrik:BAABNQAECn8tAAMKAAgKsR+nTgCaAgAKAAgKsR+nTgCaAgAiAAEK0R0jMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8WAAMdAAcKQxT/FgC8AAABAAcKQxSndQC2AQAdAAQKMwv/FgC8AAAAAA==.Volklin:BAAANQAECgUIBQAAAA==.Voyageurs:BAABNQAECn8dAAIVAAkKMRwcBwDuAgAVAAkKMRwcBwDuAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggICQAOAAAAAA==.Vyrka:BAAANQAECgQIDQAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBgABNQAECgkJKAALAJodAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcICgAAAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgQIBwAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECgYIEQAOAAAAAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQAOAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAABNQAECn8bAAMQAAcK9BVRDwBIAQARAAYKBBdAHACFAQAQAAYKahNRDwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECggIEAAOAAAAAA==.Wonyoung:BAAANQAECggIEAAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.',
Wu='Wuthrad:BAAANQAECgYIDwAAAA==.',
Wy='Wyze:BAAANQADCggIDgAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAABNQAECn8gAAMGAAkKVx3fIQB7AgAGAAkKVx3fIQB7AgAFAAIKMAOR0QBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAABNQAECn8ZAAIBAAkKdRI+TgA2AgABAAkKdRI+TgA2AgAAAA==.Xilhaunt:BAABNQAECn8vAAQTAAkKCBukBQC6AgATAAkKkxikBQC6AgAIAAkKQhUkTABsAgAfAAQKShRuFQDwAAAAAA==.',
Xo='Xoilbiis:BAAANQADCgYIEQAAAA==.Xoilkick:BAAANQAECgcIDwAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQAECgUICgAAAA==.',
['Xê']='Xêna:BAAANQAECgUICgAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgkJNgASAPgfAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgYICgAAAA==.',
Za='Zaak:BAABNQAECn8fAAIjAAgKJSVfAQBfAwAjAAgKJSVfAQBfAwAAAA==.Zamari:BAAANQAECgQICQAAAA==.Zanzabar:BAAANQAECgcICQAAAA==.',
Ze='Zelfie:BAAANQAECgEJAQAAAA==.Zeliek:BAABNQAECn8rAAIJAAkK7xpeIQDmAgAJAAkK7xpeIQDmAgABNQAECgkJKwAJAO8aAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.',
Zo='Zoerina:BAAANQAECgYIDQAAAA==.Zoobilong:BAABNQAECn8gAAIDAAkKqxBegAAjAgADAAkKqxBegAAjAgAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECggIHwAjACUlAA==.',
['Zë']='Zën:BAABNQAECn8nAAMMAAkKSAlH2QDRAQAMAAkKeghH2QDRAQALAAEKCQ9KTAAsAAAAAA==.',
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
