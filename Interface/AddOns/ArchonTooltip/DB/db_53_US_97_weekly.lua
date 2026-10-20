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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Warlock-Destruction','Druid-Guardian','Druid-Feral','Paladin-Protection','Monk-Brewmaster','Warrior-Protection','Hunter-BeastMastery','Monk-Windwalker','Druid-Restoration','Priest-Discipline','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Warrior-Fury','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQADCgYIBgAAAA==.',
Ae='Aenimal:BAAANQAECgQIBAAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECgoKLwABAKEWAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.',
Am='Amberlie:BAAANQAECggICQAAAA==.Aminni:BAABNQAECn8cAAICAAgKVxHcZQDbAQACAAgKVxHcZQDbAQAAAA==.Amorgal:BAAANQADCgYICQAAAA==.Amorir:BAABNQAECn8hAAIDAAoKfhJVEAD4AQADAAoKfhJVEAD4AQAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAABNQAECn8fAAIEAAgKRBDzHAAAAQAEAAgKRBDzHAAAAQAAAA==.Andeddo:BAABNQAECn8yAAQFAAoKmh3bGQDyAgAFAAkKOx3bGQDyAgAGAAgKHBSJPwDLAQAHAAQK+RgBFwAwAQAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAABNQAECn8fAAIEAAoKcxtrAwBAAgAEAAoKcxtrAwBAAgAAAA==.Ariodecay:BAAANQAECgQIBgAAAA==.Ariodh:BAACNQAFFH8YAAMIAAcKmCM5AQBgAQAJAAYKyiWbBAAgAgAIAAUKHBg5AQBgAQA1AAQKfy8AAwkACgpiJpgCAMwDAAkACgpiJpgCAMwDAAgAAwo0HhweAL8AAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBAAAAA==.Arnak:BAAANQADCgMJAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8OAAIKAAQKABOfGwAaAQAKAAQKABOfGwAaAQA1AAQKfzAAAgoACgrmHYgjAGABAAoACgrmHYgjAGABAAAA.',
At='Athenà:BAAANQABCgQJBwAAAA==.Atonedaka:BAAANQAECgIIAQABNQAECgkJHAALAOUfAA==.',
Av='Avye:BAABNQAECn8eAAMMAAYKxRuvKgASAQAMAAYKxRuvKgASAQACAAEKSgbtLQEhAAAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgYIBgAAAA==.Banthr:BAABNQAECn8XAAINAAgKRA7NpADBAQANAAgKRA7NpADBAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Beeps:BAAANQAECgUIBQAAAA==.Benchedwin:BAAANQADCggIDgAAAA==.',
Bi='Bigcow:BAABNQAECn8UAAIMAAcKnhHNgQCgAQAMAAcKnhHNgQCgAQAAAA==.Bigdeeps:BAABNQAECn8lAAINAAoK4CL0GwBIAwANAAoK4CL0GwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn8pAAIBAAkKTCKoAgAxAwABAAkKTCKoAgAxAwAAAA==.Blastcannon:BAABNQAECn8gAAMOAAgKowMTHgD8AAAOAAcK1wMTHgD8AAAPAAQK5QGhrwFiAAAAAA==.Bluejuly:BAAANQABCgQJBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAFFAIIBgAQAN0TAA==.',
Br='Bravehearth:BAAANQAECgYIBwABNQAECgUIBQARAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8gAAIEAAgKVRJ9QAD4AQAEAAgKVRJ9QAD4AQAAAA==.Bulan:BAABNQAECn8mAAISAAkKiCMlBgA5AwASAAkKiCMlBgA5AwAAAA==.',
Ca='Candypants:BAABNQAECn8mAAISAAkKbBg7CgAzAQASAAkKbBg7CgAzAQAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECn8rAAIOAAkKWiJ9AwANAwAOAAkKWiJ9AwANAwAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAAANQAECgUICwAAAA==.Cayssaris:BAAANQAECgQIEQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn8oAAMTAAkKXh1+BAC/AgATAAkK/Bx+BAC/AgAUAAYKNRsxGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgEIAQABNQAECggIEwARAAAAAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chappedlips:BAAANQAECgEIAQAAAA==.Cheetor:BAAANQAECggICQABNQAECgoKPAAVAKUfAA==.Chidaka:BAAANQAECgIIAgABNQAECgkJHAALAOUfAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAACNQAFFH8GAAIKAAMKoQ07EACaAAAKAAMKoQ07EACaAAA1AAQKfyEAAwoACgpAFqYqAEgBAAoACAq0GqYqAEgBABYABQqBDas3AOIAAAAA.Cosairi:BAABNQAECn8aAAICAAcKxRTqggCDAQACAAcKxRTqggCDAQAAAA==.Cougztroll:BAABNQAECn8fAAMXAAoK+xFdCAB2AQAXAAkKoBFdCAB2AQAYAAEKeBTzPgA+AAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8WAAIQAAkKjh+tDQCRAgAQAAkKjh+tDQCRAgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgkJKAATAF4dAA==.',
Cu='Cuttercupx:BAAANQAECgUICgABNQAECgcIDQARAAAAAA==.',
Da='Dakadin:BAABNQAECn8cAAILAAkK5R+vJADYAgALAAkK5R+vJADYAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn8wAAIDAAoKGhkRVACZAgADAAoKGhkRVACZAgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn88AAIHAAgKcBBYGAAnAQAHAAgKcBBYGAAnAQAAAA==.Dashy:BAAANQAECgUIBQAAAA==.Dawnstone:BAAANQAECgQIDAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn8hAAMWAAoKIRViBgC+AAAKAAkKLhTKNwAjAQAWAAQKJhFiBgC+AAAAAA==.Deafsmash:BAAANQAECgIIBAABNQAECggIKwAFAJQgAA==.Delamyr:BAAANQABCgIJAwABNQADCgYIBgARAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQAECgQIBAABNQAECgUIEAARAAAAAA==.Destroyevsky:BAAANQAECgQIDAAAAA==.Detonate:BAAANQADCgUICQAAAA==.',
Di='Digem:BAAANQABCgQJBAABNQADCgcIEwARAAAAAA==.Dixinu:BAAANQAECgIIAgAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhn+FwDoAAADAAMKPhn+FwDoAAAZAAIKYwrbDgBYAAA1AAQKfyYAAwMACQpgI3kdAE0DAAMACQpgI3kdAE0DABkABAo7GXpAAPcAAAAA.Dotsonyourpp:BAAANQADCgQIBAABNQAECgUICwARAAAAAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJIQASADAgAA==.Dragonwarior:BAABNQAECn8aAAINAAoK4w5xowDEAQANAAoK4w5xowDEAQAAAA==.Drykkr:BAABNQAECn8UAAIaAAYKuht7FQCMAQAaAAYKuht7FQCMAQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggICQARAAAAAA==.Element:BAAANQADCgUIBQAAAA==.Elpollo:BAAANQAECgUICwAAAA==.Elvar:BAAANQADCgYIFAAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgoKJAADAPoQAA==.',
Ep='Epitome:BAABNQAECn8mAAMOAAoKMhn4AQDTAQAOAAoKMhn4AQDTAQAPAAEKAABqyQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.',
Et='Ethereal:BAAANQADCgIIAgAAAA==.Etude:BAAANQAECgQIBgAAAA==.',
Eu='Eunha:BAAANQAECgYIDwABNQAECggIEwARAAAAAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECggIPAAHAHAQAA==.Evergrey:BAAANQAECgUIBQAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQADCggICgAAAA==.Falasdaer:BAAANQAECgQICAAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fatalis:BAAANQADCggIHgAAAA==.Fatterblunt:BAACNQAFFH8UAAIEAAYKjwxTBAAsAQAEAAYKjwxTBAAsAQA1AAQKfy4AAgQACgo9GmosAHgCAAQACgo9GmosAHgCAAAA.',
Fe='Feldar:BAABNQAECn8lAAIDAAoK3xrXXQB/AgADAAoK3xrXXQB/AgAAAA==.Feronite:BAACNQAFFH8GAAIQAAIK3RPCAgCYAAAQAAIK3RPCAgCYAAA1AAQKfzwAAhAACgrmH+cGABQDABAACgrmH+cGABQDAAAA.',
Fi='Fizzleclaw:BAABNQAECn8YAAMEAAoKIRWpBgDNAQAEAAkKTBGpBgDNAQAXAAYK8Rw0HwClAQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgoKGAAEACEVAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fl='Fluchtweg:BAAANQAECggIBgABNQAECgoKIQAYAHYeAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgUIDQAAAA==.',
Fr='Fredwin:BAAANQAECggIEQAAAA==.Free:BAAANQADCgcIDQABNQAECgQIBAARAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBAARAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Ganthex:BAAANQADCgUJBQAAAA==.Gapper:BAABNQAECn88AAIVAAoKpR9ZAwDsAQAVAAoKpR9ZAwDsAQAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAbALwgAA==.Gargodath:BAAANQABCggIEAAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECn8iAAIcAAkKZhs+KgDwAgAcAAkKZhs+KgDwAgAAAA==.Glitterpants:BAAANQAECgUIBQAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8dAAINAAgKxRMRfgAgAgANAAgKxRMRfgAgAgAAAA==.',
Go='Gojira:BAAANQAECgUIEQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECn8hAAMSAAgKdBoDEwBNAgASAAgKdBoDEwBNAgAdAAEKCA+KbAAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIDwARAAAAAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAABNQAECn8ZAAINAAkKEw8HHwCIAQANAAkKEw8HHwCIAQAAAA==.',
Ha='Haerin:BAAANQAECgYIDAABNQAECggIEwARAAAAAA==.Harnel:BAABNQAECn8cAAIDAAYKGAQnHwHrAAADAAYKGAQnHwHrAAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgYIBgAAAA==.Hellborne:BAAANQABCgIIAgABNQAECgQIBAARAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQARAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQAECgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAFFAIIBgAQAN0TAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgYIBgAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAABNQAECn8YAAIPAAoKJh3zNAAgAwAPAAoKJh3zNAAgAwAAAA==.Kaliel:BAAANQADCgcIGAAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgYIBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwAKAEsRAA==.',
Ke='Kernelpanic:BAACNQAFFH8VAAQFAAYK7R6bAACAAQAFAAUKRh6bAACAAQAGAAIKZBmZFACZAAAHAAIKAAAlNgAnAAA1AAQKfyIAAwUACQrpIEgtAH4CAAUACQrpIEgtAH4CAAYAAQolFsWoADsAAAAA.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYIDgAAAA==.Kirkle:BAABNQAECn8wAAIWAAkKyxodBgCtAgAWAAkKyxodBgCtAgAAAA==.',
Ko='Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYICgAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwAKAEsRAA==.Krukar:BAAANQAECgQIDAAAAA==.',
Ku='Kulrath:BAAANQAECggIDAAAAA==.',
Kw='Kwovie:BAABNQAECn8eAAIXAAkK4BneEABTAgAXAAkK4BneEABTAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8YAAIDAAgKvw9CqgDLAQADAAgKvw9CqgDLAQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgYICgABNQAECgYIDQARAAAAAA==.Lavasaurus:BAAANQAECgYIDQAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAAANQAECggIEAAAAA==.',
Li='Lifebloomz:BAABNQAECn8ZAAMeAAgKYBFqKgDLAQAeAAgKYBFqKgDLAQAXAAEK3wHxcgAZAAAAAA==.Lilfluffcc:BAABNQAECn8fAAIQAAkKtBF1EQBSAgAQAAkKtBF1EQBSAgAAAA==.',
Lo='Lockward:BAABNQAECn8jAAIKAAoKHBhXIwBhAQAKAAoKHBhXIwBhAQAAAA==.Lorblor:BAABNQAECn8WAAIJAAcKPh9oLgAyAgAJAAcKPh9oLgAyAgAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8iAAIMAAgKRhhuVgAgAgAMAAgKRhhuVgAgAgAAAA==.Lunafox:BAABNQAECn8ZAAMMAAoKHgoFIQA3AQAMAAcK+AkFIQA3AQACAAkKHQkxoQAzAQAAAA==.Lunamae:BAABNQAECn8cAAIPAAgKvQ3SzgDoAQAPAAgKvQ3SzgDoAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgoKMwABAAAbAA==.Luvvyyaa:BAABNQAECn8zAAMBAAoKABvTPgBvAgABAAoKABvTPgBvAgAfAAIKwQp8IABeAAAAAA==.Luvyya:BAAANQAECgUICgABNQAECgoKMwABAAAbAA==.',
Ly='Lythomancer:BAABNQAECn8cAAIWAAcKqQcAIQBpAQAWAAcKqQcAIQBpAQAAAA==.',
Ma='Maddeena:BAAANQAECgYIDgAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAIKAAUKSxGYEQBzAQAKAAUKSxGYEQBzAQA1AAQKfzEAAgoACQpUIq8ZACADAAoACQpUIq8ZACADAAAA.',
Mc='Mcmercie:BAABNQAECn8aAAIZAAkKZg73IwDBAQAZAAkKZg73IwDBAQAAAA==.',
Me='Mechacooter:BAABNQAECn8oAAIgAAoKSRjjGwCfAgAgAAoKSRjjGwCfAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8hAAIPAAcKrBIN3wDKAQAPAAcKrBIN3wDKAQAAAA==.Melchiorr:BAABNQAECn82AAIhAAoK0xqSAgD0AgAhAAoK0xqSAgD0AgAAAA==.Melynne:BAABNQAECn8fAAICAAoKxA7DFwCZAQACAAoKxA7DFwCZAQAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQIBwARAAAAAA==.Minji:BAAANQAECgYIDQABNQAECggIEwARAAAAAA==.Minsoo:BAABNQAECn8lAAISAAoKYB/7AwDbAQASAAoKYB/7AwDbAQAAAA==.',
Ml='Mlrgl:BAABNQAECn8eAAMcAAoK4yESDQAJAgAcAAoK4yESDQAJAgAVAAUKRxB3RgAnAQAAAA==.Mlrglo:BAAANQAECgUJBgABNQAECgoKHgAcAOMhAA==.',
Mo='Mormegil:BAABNQAECn8XAAQGAAkKphbpDACfAQAGAAgK4xLpDACfAQAHAAUKbhnYagBIAQAFAAMKIx2kjADyAAAAAA==.Moshimoshi:BAABNQAFFH8LAAMCAAQK+RLMCgDRAAACAAMKrQ7MCgDRAAAMAAEKAAAMGgAAAAAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQAECgUIEAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQAECggICAABNQAECgoKKAAgAEkYAA==.',
Ne='Nessará:BAABNQAECn8sAAIBAAgKvwzaIACAAQABAAgKvwzaIACAAQAAAA==.',
Ni='Nightgodjuju:BAABNQAECn8XAAIOAAgKfw7sBABaAQAOAAgKfw7sBABaAQAAAA==.Nikna:BAAANQAECgUICwABNQAFFAMIBwAcACcdAA==.',
Nu='Nudacris:BAAANQAECggIDwABNQAECgoKHgAcAOMhAA==.Nuraga:BAABNQAECn8fAAIbAAgK8yJcBQAhAwAbAAgK8yJcBQAhAwAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAABNQAECn8XAAIVAAgK6BaBNQCiAQAVAAgK6BaBNQCiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAABNQAECn8hAAISAAkKMCC3BgArAwASAAkKMCC3BgArAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECggIEAARAAAAAA==.Pattilicious:BAABNQAECn8UAAIDAAgK7Q3NvgCfAQADAAgK7Q3NvgCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8iAAMUAAoKTxdDFwDXAQAUAAcKhxdDFwDXAQAiAAgKXhYPCABDAQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn8wAAMZAAoKpxJEBgCbAQAZAAoKpxJEBgCbAQADAAIK5gs9cAFuAAAAAA==.',
Py='Pyrug:BAAANQADCgYICwABNQAECgoKIQAWACEVAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgoKKwAcAEYOAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rannmagnison:BAABNQAECn8iAAIDAAgKuwYx6QBJAQADAAgKuwYx6QBJAQAAAA==.Raquoon:BAAANQAECgQIEQAAAA==.Razzalghoul:BAABNQAECn8ZAAMGAAgK9hEOPwDOAQAGAAgK9hEOPwDOAQAFAAQKEQd2qgChAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECgUIEAARAAAAAA==.Reuli:BAAANQAECgIIAwAAAA==.Reze:BAABNQAECn8fAAIdAAoK8CF9DgD4AgAdAAoK8CF9DgD4AgABNQAFFAkJKQAJAPAjAA==.',
Rh='Rhaeynera:BAABNQAECn8aAAIUAAYKmQTEKADpAAAUAAYKmQTEKADpAAAAAA==.Rhinne:BAAANQADCgYIBgAAAA==.',
Ri='Riezen:BAABNQAECn8hAAIFAAYKUxhKZgB4AQAFAAYKUxhKZgB4AQAAAA==.Rinorik:BAABNQAECn8hAAMKAAcK0x4JbwASAgAKAAYKnh4JbwASAgAWAAIK3B+/QwC2AAAAAA==.',
Ro='Rockbiter:BAAANQADCgYIBgAAAA==.Rockhhard:BAAANQAECgIIAgAAAA==.Roeken:BAABNQAECn8nAAINAAkKQRH/HwCEAQANAAkKQRH/HwCEAQAAAA==.Rollingman:BAAANQAECgYICQAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8fAAIHAAgKmCKbFQAAAwAHAAgKmCKbFQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECn8dAAIVAAcKXyMSEwDJAgAVAAcKXyMSEwDJAgAAAA==.',
Sa='Samsó:BAABNQAECn8rAAMLAAkK/RZXCQAuAgALAAkK/RZXCQAuAgADAAEKAACoowE1AAAAAA==.Sapharina:BAABNQAECn8vAAIBAAoKoRZwDAAgAgABAAoKoRZwDAAgAgAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8hAAQYAAoKdh61CADHAgAYAAoKdh61CADHAgAeAAYKwBl5LAC4AQAXAAIKUg22UABgAAAAAA==.Schreckstoff:BAABNQAECn8iAAIMAAgKmBQLXQALAgAMAAgKmBQLXQALAgAAAA==.',
Se='Searfang:BAABNQAECn8pAAIMAAoKMhnGDQCkAQAMAAoKMhnGDQCkAQAAAA==.Sematic:BAAANQAECgMIBgABNQAFFAcIGgANAL0dAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shamor:BAAANQAECgQIBQAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA2HVQCCAQAEAAcKvA2HVQCCAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAABNQAECn8iAAIYAAkKuxU7DwAdAgAYAAkKuxU7DwAdAgAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skëëts:BAAANQAECgIIAgAAAA==.',
Sl='Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAARAAAAAA==.Smashmaster:BAAANQAECgQICQAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwARAAAAAA==.',
Sn='Snowscayia:BAABNQAECn9cAAMeAAoKwx+MBgBaAwAeAAoKwx+MBgBaAwAEAAgK4xVlFwAkAQAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBziIQC/AgAEAAkKbBziIQC/AgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8hAAIOAAcKRRxKCwAOAgAOAAcKRRxKCwAOAgAAAA==.',
Sq='Squadie:BAABNQAECn8jAAIcAAkKlApzjQDvAQAcAAkKlApzjQDvAQAAAA==.Squanchs:BAACNQAFFH8IAAICAAIKRCVjCwDFAAACAAIKRCVjCwDFAAA1AAQKfykAAgIACgojJeADAKwDAAIACgojJeADAKwDAAE1AAQKBggHABEAAAAA.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgcICQAAAA==.',
St='Stoot:BAAANQABCgIIAQABNQAECgQIEgARAAAAAA==.Story:BAAANQADCgUICwAAAA==.Styrcius:BAABNQAECn8qAAIZAAkKdhxdAwDtAQAZAAkKdhxdAwDtAQAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECggIEAAAAA==.Suniah:BAABNQAECn8UAAMbAAcKPAgMJQAdAQAbAAcKnQcMJQAdAQANAAYKvgZ95wAWAQAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAcIGgANAL0dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQAECgIIAQAAAA==.Süß:BAAANQADCgIIAgABNQAECgoKIQAYAHYeAA==.',
Ta='Tabius:BAABNQAECn8UAAIYAAYKKBnXEwC/AQAYAAYKKBnXEwC/AQAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.Taln:BAAANQABCgEIAQABNQAECgkJFwAGAKYWAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDQARAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAAANQAECgYIDgAAAA==.',
Th='Thelorìn:BAABNQAECn8eAAIXAAkKexsoDQCUAgAXAAkKexsoDQCUAgAAAA==.Thiccdiq:BAABNQAECn8jAAMaAAcKBh88CwBZAgAaAAcKBh88CwBZAgAdAAIKKg1uJQCGAAAAAA==.Thiccgirl:BAAANQABCgMIBAAAAA==.Thirstycow:BAABNQAECn8aAAMCAAkKNQWvoAA1AQACAAkKNQWvoAA1AQAMAAcKoAIpxwAEAQAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQAECgUIBQAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECn8/AAIcAAoKrSEKCACdAwAcAAoKrSEKCACdAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAACNQAFFH8IAAIEAAQK/QWACgCpAAAEAAQK/QWACgCpAAA1AAQKfywAAgQACgoYHFAeANgCAAQACgoYHFAeANgCAAAA.Tråitors:BAABNQAECn8gAAIKAAgKDBH3MgAwAQAKAAgKDBH3MgAwAQAAAA==.',
Ts='Tsarevich:BAABNQAECn8XAAIPAAUKFQf7mQCVAAAPAAUKFQf7mQCVAAAAAA==.',
Tw='Twileaf:BAABNQAECn8bAAIeAAYKAgnTRgD7AAAeAAYKAgnTRgD7AAAAAA==.',
Ul='Ully:BAAANQAECgYIDwAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIFAAgKIhMCWQCsAQAFAAgKIhMCWQCsAQAAAA==.Unug:BAAANQADCggIDgABNQAECgoKIQAWACEVAA==.',
Ut='Uthmansur:BAAANQAECgUIEAAAAA==.',
Va='Varkbyte:BAAANQAECgUIEQAAAA==.Varrik:BAABNQAECn8tAAMNAAgKsR8YUACZAgANAAgKsR8YUACZAgAjAAEK0R3NMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8dAAMBAAgKURiCEwDXAQABAAgKURiCEwDXAQAfAAQKMwsyFwC8AAAAAA==.Volklin:BAAANQAECgUICQAAAA==.Voyageurs:BAABNQAECn8hAAIYAAoKrRtEBwDuAgAYAAoKrRtEBwDuAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggICQARAAAAAA==.Vyrka:BAABNQAECn8XAAIcAAUKuQp8fAC0AAAcAAUKuQp8fAC0AAAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBgABNQAECgkJKAAOAJodAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcICgAAAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgUICAAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECggIIAAKAAwRAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQARAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Windsslashh:BAAANQAECgEIAQAAAA==.Wish:BAABNQAECn8fAAMTAAcK9BV5DwBIAQAUAAYKBBd8HACFAQATAAYKahN5DwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECggIEwARAAAAAA==.Wonyoung:BAAANQAECggIEwAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.',
Wu='Wuthrad:BAAANQAECgYIDwAAAA==.',
Wy='Wyze:BAAANQAECgEIAQAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAABNQAECn8iAAMGAAkKxB2IIgB6AgAGAAkKxB2IIgB6AgAFAAIKMAPW0wBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAABNQAECn8hAAIBAAoKlxgxCwAxAgABAAoKlxgxCwAxAgAAAA==.Xilhaunt:BAABNQAECn8zAAQWAAoKnxurBQC6AgAWAAkKkxirBQC6AgAKAAoKSReFTQBrAgAhAAQKShSnFQDwAAAAAA==.',
Xo='Xoilkick:BAAANQAECggIDwAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQAECgcIEAAAAA==.Xorm:BAAANQAECgEIAQAAAA==.',
['Xê']='Xêna:BAAANQAECgUICwAAAA==.',
['Xì']='Xì:BAAANQAECgEIAQAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgoKPAAVAKUfAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgYICwAAAA==.',
Za='Zaak:BAABNQAECn8oAAIkAAoKtiQ0AADeAgAkAAoKtiQ0AADeAgAAAA==.Zamari:BAAANQAECgQIDgAAAA==.Zanzabar:BAAANQAECggIDwAAAA==.',
Ze='Zelfie:BAAANQAECgIIAQAAAA==.Zeliek:BAABNQAECn8xAAILAAoKqRvrIQDlAgALAAoKqRvrIQDlAgABNQAECgoKMQALAKkbAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.Zeus:BAAANQADCgIIAQAAAA==.',
Zo='Zoerina:BAABNQAECn8WAAIKAAoKqg0QFgCdAQAKAAoKqg0QFgCdAQAAAA==.Zoobilong:BAABNQAECn8kAAIDAAoK+hB9ggAjAgADAAoK+hB9ggAjAgAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECgoKKAAkALYkAA==.',
['Zë']='Zën:BAABNQAECn8uAAMPAAoK2wvoJQB+AQAPAAoK2wvoJQB+AQAOAAEKCQ8xTQAsAAAAAA==.',
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
