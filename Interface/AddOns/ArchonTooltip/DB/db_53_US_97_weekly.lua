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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Warlock-Destruction','Druid-Feral','Evoker-Preservation','Paladin-Protection','Monk-Brewmaster','Warrior-Protection','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Warlock-Affliction','Warrior-Fury','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQAECgEIAQAAAA==.',
Ae='Aenimal:BAAANQAECgQIBAAAAA==.',
Ah='Ahavati:BAAANQAECgEIAQAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECgoKMwABAHgXAA==.Akittymeow:BAAANQAECgIIAwAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.',
Am='Amberlie:BAAANQAECggICgAAAA==.Aminni:BAABNQAECn8gAAICAAgKVxHcZQDbAQACAAgKVxHcZQDbAQAAAA==.Amorgal:BAAANQADCgYICQAAAA==.Amorir:BAABNQAECn8qAAIDAAoKxhTJPwD8AQADAAoKxhTJPwD8AQAAAA==.Amorydalias:BAAANQAECgMIBQAAAA==.',
An='Anastala:BAABNQAECn8gAAIEAAgKRBAsSQDEAQAEAAgKRBAsSQDEAQAAAA==.Andeddo:BAACNQAFFH8GAAMFAAIKuhJqFQBsAAAFAAIKFg1qFQBsAAAGAAEKWRZ3HgBTAAA1AAQKfzkABAYACgqaHdsZAPICAAYACQo7HdsZAPICAAcACAocFIk/AMsBAAUABAr5GF0zABwBAAAA.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJBAAAAA==.',
Ar='Archontas:BAABNQAECn8gAAIEAAoKFR22GwDrAgAEAAoKFR22GwDrAgAAAA==.Ariodecay:BAAANQAECgUICAAAAA==.Ariodh:BAACNQAFFH8ZAAMIAAcKmCObBAAgAgAIAAYKyiWbBAAgAgAJAAYKHBhlAgBPAQA1AAQKfzgABAgACgqhJpgCAMwDAAgACgpiJpgCAMwDAAoABgqeJtEDADYCAAkABQpWIRAXAIMBAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBQAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8PAAILAAUKABOfGwAaAQALAAUKABOfGwAaAQA1AAQKfzQAAgsACgovHuVBAIwCAAsACgovHuVBAIwCAAAA.',
At='Athenà:BAAANQABCgYICQAAAA==.Atonedaka:BAAANQAECgIIBQABNQAECgoKJQAMAGEgAA==.',
Av='Avye:BAABNQAECn8mAAMNAAYKix2NfQCrAQANAAYKix2NfQCrAQACAAEKSgbtLQEhAAAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgcIDgAAAA==.Banthr:BAABNQAECn8XAAIOAAgKRA7NpADBAQAOAAgKRA7NpADBAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Beeps:BAAANQAECgUIBgAAAA==.Benchedwin:BAAANQAECgIIAgAAAA==.',
Bi='Bigcow:BAABNQAECn8UAAINAAcKnhHNgQCgAQANAAcKnhHNgQCgAQAAAA==.Bigdeeps:BAABNQAECn8oAAIOAAoKASP0GwBIAwAOAAoKASP0GwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn8xAAIBAAkKriKqBwBkAwABAAkKriKqBwBkAwAAAA==.Blastcannon:BAABNQAECn8gAAMPAAgKowMTHgD8AAAPAAcK1wMTHgD8AAAQAAQK5QGhrwFiAAAAAA==.Bluejuly:BAAANQABCgYICQAAAA==.Blutønium:BAAANQAECgEIAQAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQAECgEIAQABNQAFFAMICQARAPESAA==.',
Br='Bravehearth:BAAANQAECgYIDQABNQAECgUIBQASAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8nAAMEAAgKjRJ9QAD4AQAEAAgKjRJ9QAD4AQATAAEKmgCgZgANAAAAAA==.Bulan:BAABNQAECn8qAAIUAAkK1SMlBgA5AwAUAAkK1SMlBgA5AwAAAA==.',
Ca='Candypants:BAABNQAECn8vAAMUAAoK9Be+CgD6AQAUAAoK9Be+CgD6AQAVAAEKMgfwSAA0AAAAAA==.Caoth:BAAANQAECgQIBwAAAA==.Cappilon:BAABNQAECn8tAAIPAAkKWiJ9AwANAwAPAAkKWiJ9AwANAwAAAA==.Carcus:BAAANQAECgcIEQAAAA==.Cayleedah:BAAANQAECgYIDwAAAA==.Cayssaris:BAABNQAECn8UAAIWAAUKBB4pIgD4AAAWAAUKBB4pIgD4AAAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn8wAAMXAAkKXh1+BAC/AgAXAAkK/Bx+BAC/AgAYAAYKNRsxGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgMIAwABNQAECgkJHAABAIAhAA==.Chaoticoreo:BAAANQAECgEIAgAAAA==.Chappedlips:BAAANQAECggICQAAAA==.Cheetor:BAAANQAECggICQABNQAECgoKRQAZADcgAA==.Chidaka:BAAANQAECgIIBgABNQAECgoKJQAMAGEgAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAACNQAFFH8HAAILAAQKoQ17GgCQAAALAAQKoQ17GgCQAAA1AAQKfyYAAwsACgqZGCcvAPIBAAsACgqZGCcvAPIBABoABQqBDas3AOIAAAAA.Cosairi:BAABNQAECn8aAAICAAcKxRTqggCDAQACAAcKxRTqggCDAQAAAA==.Cougztroll:BAABNQAECn8hAAMWAAoK+xH+FwBPAQAWAAkKoBH+FwBPAQAbAAEKeBTzPgA+AAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8aAAIRAAkK9iGtDQCRAgARAAkK9iGtDQCRAgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgkJMAAXAF4dAA==.',
Cu='Cuttercupx:BAAANQAECgUICwABNQAECgcIDwASAAAAAA==.',
Da='Dahn:BAAANQAECgcIBgABNQAECgoKRQAZADcgAA==.Dakadin:BAABNQAECn8lAAIMAAoKYSDoFQCUAgAMAAoKYSDoFQCUAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn80AAIDAAoK+hkRVACZAgADAAoK+hkRVACZAgAAAA==.Darkenedstar:BAAANQAECgEIAQABNQAECgQIBAASAAAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn9CAAMFAAkKpQ7BMwAaAQAFAAgKcBDBMwAaAQAHAAEK5QNpkAApAAAAAA==.Dashy:BAAANQAECgUIBgAAAA==.Dawnstone:BAAANQAECgQIDQAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn8qAAMaAAoKuRYlCADtAAALAAoKYhXHNQDTAQAaAAUK9BElCADtAAAAAA==.Deafsmash:BAAANQAECgIIBwABNQAECggILQAGAJQgAA==.Delamyr:BAAANQABCgIIAwABNQADCgYIBgASAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Delusional:BAAANQAECgEIAQAAAA==.Denaric:BAAANQAECgUICQABNQAECgYIGgAcAJgQAA==.Destroyevsky:BAAANQAECgYIEgAAAA==.Detonate:BAAANQAECggIDAAAAA==.',
Di='Digem:BAAANQAECgEIAgABNQAECgIIBwASAAAAAA==.Dixinu:BAAANQAECgIIAwAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhn+FwDoAAADAAMKPhn+FwDoAAAdAAIKYwrbDgBYAAA1AAQKfyYAAwMACQpgI3kdAE0DAAMACQpgI3kdAE0DAB0ABAo7GXpAAPcAAAAA.Dotsonyourpp:BAAANQADCgQIBAABNQAECgcIFQAQAFAYAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJIwAUAMcgAA==.Dragonwarior:BAABNQAECn8cAAIOAAoK4w5xowDEAQAOAAoK4w5xowDEAQAAAA==.Drykkr:BAABNQAECn8UAAIeAAYKuht7FQCMAQAeAAYKuht7FQCMAQAAAA==.',
Eh='Ehlana:BAAANQAECgEIAQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggICgASAAAAAA==.Element:BAAANQAECgEIAQAAAA==.Ellipsis:BAAANQAECgEIAQAAAA==.Elpollo:BAABNQAECn8VAAIQAAcKUBiWcABkAQAQAAcKUBiWcABkAQAAAA==.Elvar:BAAANQAECgEIAgAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgoKJgADAPoQAA==.',
Ep='Epitome:BAABNQAECn8vAAMPAAoKMhlABAAxAgAPAAoKMhlABAAxAgAQAAIKegJqyQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEwAAAA==.',
Et='Ethereal:BAAANQADCgIIAgAAAA==.Etude:BAAANQAECgQIBgABNQAFFAUIDAACABsRAA==.',
Eu='Eunha:BAABNQAECn8WAAIUAAgKoBtMCQAqAgAUAAgKoBtMCQAqAgABNQAECgkJHAABAIAhAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgkJQgAFAKUOAA==.Evergrey:BAAANQAECgUIDQAAAA==.Evermoons:BAABNQAECn8UAAITAAYK8hicLgCmAQATAAYK8hicLgCmAQAAAA==.',
Fa='Falaria:BAAANQAECgEIAQAAAA==.Falasdaer:BAAANQAECgQICQAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fatalis:BAAANQAECgEIAQAAAA==.Fatterblunt:BAACNQAFFH8VAAIEAAYKjwy2BwAbAQAEAAYKjwy2BwAbAQA1AAQKfzIAAgQACgptHGosAHgCAAQACgptHGosAHgCAAAA.',
Fe='Feldar:BAABNQAECn8sAAIDAAoK3BzXXQB/AgADAAoK3BzXXQB/AgAAAA==.Feronite:BAACNQAFFH8JAAIRAAMK8RKEAgDgAAARAAMK8RKEAgDgAAA1AAQKfz0AAhEACgrmH+cGABQDABEACgrmH+cGABQDAAAA.',
Fi='Fizzleclaw:BAABNQAECn8gAAMEAAoKhxbfFgDpAQAEAAkKsRLfFgDpAQAWAAYK8Rw0HwClAQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgoKIAAEAIcWAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fl='Fluchtweg:BAAANQAECggIDgABNQAECgoKJgAbAHIgAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgYIEQAAAA==.',
Fr='Fredwin:BAABNQAECn8UAAILAAgKYQuusABvAQALAAgKYQuusABvAQAAAA==.Free:BAAANQAECgMIAwABNQAECgQIBQASAAAAAA==.Frenn:BAAANQAECgEIAQAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBQASAAAAAA==.Furvert:BAAANQAECgcIDwAAAA==.',
Ga='Ganthex:BAAANQADCgUIBQAAAA==.Gapper:BAABNQAECn9FAAIZAAoKNyAyCQBAAwAZAAoKNyAyCQBAAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAfALwgAA==.Gargodath:BAAANQABCggIEAAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECn8lAAIgAAoKgRs+KgDwAgAgAAoKgRs+KgDwAgAAAA==.Glitterpants:BAAANQAECgcIBwAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8fAAIOAAkKlxURfgAgAgAOAAkKlxURfgAgAgAAAA==.',
Go='Gojira:BAABNQAECn8YAAIMAAUKfiGFMADiAQAMAAUKfiGFMADiAQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECn8iAAMUAAgKdBoDEwBNAgAUAAgKdBoDEwBNAgAVAAEKCA+KbAAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIEwASAAAAAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAABNQAECn8hAAIOAAoKUhEKOQDuAQAOAAoKUhEKOQDuAQAAAA==.',
Ha='Haerin:BAAANQAECgYIDQABNQAECgkJHAABAIAhAA==.Hairydresden:BAAANQAECgEIBQAAAA==.Harnel:BAABNQAECn8cAAIDAAYKGAQnHwHrAAADAAYKGAQnHwHrAAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgYICwAAAA==.Hellborne:BAAANQAECgEIAQABNQAECgQIBAASAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDwASAAAAAA==.Hoyer:BAAANQAECgIIBAAAAA==.',
Hu='Humbledrink:BAAANQAECgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBQAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAFFAMICQARAPESAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgYICAAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIBAAAAA==.',
Ka='Kaiserice:BAABNQAECn8aAAIQAAoKrB3zNAAgAwAQAAoKrB3zNAAgAwAAAA==.Kaliel:BAAANQADCggIGAAAAA==.Kamarra:BAAANQAECgEIAwAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgYIBgAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwALAEsRAA==.',
Ke='Kernelpanic:BAACNQAFFH8WAAQGAAYK7R5fAQB2AQAGAAUKRh5fAQB2AQAHAAIKZBmZFACZAAAFAAIKAAAlNgAnAAA1AAQKfygAAwYACgopIs4RAAcCAAYACQpaIc4RAAcCAAcAAwpYG+Z3AFwAAAAA.Keyoshi:BAAANQAECggIDwAAAA==.',
Ki='Kickrocks:BAAANQAECgEIAQAAAA==.Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQAECgEIAgAAAA==.Kirkle:BAABNQAECn86AAIaAAoKNBsxAQBZAgAaAAoKNBsxAQBZAgAAAA==.',
Ko='Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYIDAAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwALAEsRAA==.',
Ku='Kulrath:BAAANQAECggIDQAAAA==.',
Kw='Kwovie:BAABNQAECn8eAAIWAAkK4BneEABTAgAWAAkK4BneEABTAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAgAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8eAAIDAAgK9w9CqgDLAQADAAgK9w9CqgDLAQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgYICwABNQAECgYIEwASAAAAAA==.Lavasaurus:BAAANQAECgYIEwAAAA==.',
Le='Leafstorm:BAAANQAECgIIBwAAAA==.Leokenoso:BAAANQAECgMIBwAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAABNQAECn8VAAMgAAkKLguv4AA/AQAgAAgKugyv4AA/AQAZAAMKBwKBbAB8AAAAAA==.',
Li='Lifebloomz:BAABNQAECn8fAAMTAAgKVRJqKgDLAQATAAgKVRJqKgDLAQAWAAEK3wHxcgAZAAAAAA==.Lilfluffcc:BAABNQAECn8fAAIRAAkKtBF1EQBSAgARAAkKtBF1EQBSAgAAAA==.',
Lo='Lockward:BAABNQAECn8rAAMLAAoK2RnlMwDbAQALAAoKSRjlMwDbAQAaAAEK9BYdIwBHAAAAAA==.Lorblor:BAABNQAECn8cAAIIAAkK4hpoLgAyAgAIAAkK4hpoLgAyAgAAAA==.Lowang:BAAANQAECgIIAwAAAA==.Lowmeinn:BAAANQAECgUJCgAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8iAAINAAgKRhhuVgAgAgANAAgKRhhuVgAgAgAAAA==.Lunafox:BAABNQAECn8fAAMCAAoKxhAoMwDTAQACAAoKxhAoMwDTAQANAAcK+AkaUwATAQAAAA==.Lunamae:BAABNQAECn8cAAIQAAgKvQ3SzgDoAQAQAAgKvQ3SzgDoAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgoKPAABAAAbAA==.Luvvyyaa:BAABNQAECn88AAQBAAoKABvTPgBvAgABAAoKABvTPgBvAgAhAAIKwQp8IABeAAAiAAEKdwnxRQA5AAAAAA==.Luvyya:BAAANQAECgUICwABNQAECgoKPAABAAAbAA==.',
Ly='Lythomancer:BAABNQAECn8fAAIaAAkK4QcAIQBpAQAaAAkK4QcAIQBpAQAAAA==.',
Ma='Maddeena:BAABNQAECn8YAAICAAYK2whIiwCpAAACAAYK2whIiwCpAAAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAILAAUKSxGYEQBzAQALAAUKSxGYEQBzAQA1AAQKfzEAAgsACQpUIq8ZACADAAsACQpUIq8ZACADAAAA.',
Mc='Mcmercie:BAABNQAECn8dAAIdAAoKMQ/3IwDBAQAdAAoKMQ/3IwDBAQAAAA==.',
Me='Mechacooter:BAABNQAECn8pAAIjAAoKSRjjGwCfAgAjAAoKSRjjGwCfAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8hAAIQAAcKrBIN3wDKAQAQAAcKrBIN3wDKAQAAAA==.Melchiorr:BAABNQAECn86AAIkAAoKFBuSAgD0AgAkAAoKFBuSAgD0AgAAAA==.Melynne:BAABNQAECn8hAAICAAoKxA5sQwCIAQACAAoKxA5sQwCIAQAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQICQASAAAAAA==.Minji:BAABNQAECn8VAAIkAAgKOxk5BAC/AQAkAAgKOxk5BAC/AQABNQAECgkJHAABAIAhAA==.Minsoo:BAABNQAECn8uAAIUAAoKgCDNAwAcAwAUAAoKgCDNAwAcAwAAAA==.',
Ml='Mlrgl:BAABNQAECn8qAAMgAAoKUCOmIQBgAgAgAAoKUCOmIQBgAgAZAAUK0xJ3RgAnAQAAAA==.Mlrglet:BAAANQAECgcIBQABNQAECgoKKgAgAFAjAA==.Mlrglo:BAAANQAECgUJBgABNQAECgoKKgAgAFAjAA==.',
Mo='Mormegil:BAABNQAECn8aAAQHAAkKphbpKgCDAQAHAAgK9xPpKgCDAQAFAAUKbhnYagBIAQAGAAMKIx2kjADyAAAAAA==.Moshimoshi:BAACNQAFFH8MAAMCAAUKGxGkDQAHAQACAAQKag2kDQAHAQANAAEKAADPJAAAAAA1AAQKfxwAAwIACgpcFcxKADgCAAIACgpcFcxKADgCAA0AAwo6FcKJAIoAAAAA.Motosake:BAAANQADCgUIBQABNQAFFAUIDAACABsRAA==.',
Mt='Mtx:BAAANQAECgQIBAAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBgAAAA==.',
Na='Naberius:BAABNQAECn8aAAQcAAYKmBAnMQASAQAcAAUKBREnMQASAQAYAAUKmRFUEQC9AAAXAAEKAADBIABSAAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQAECggIEAABNQAECgoKKQAjAEkYAA==.',
Ne='Nessará:BAABNQAECn8wAAIBAAoKIQ0LOgDOAQABAAoKIQ0LOgDOAQAAAA==.',
Ni='Nightgodjuju:BAABNQAECn8gAAMPAAoKsQ2BCACVAQAPAAoKsQ2BCACVAQAQAAEKXwIsMwEsAAAAAA==.Nikna:BAAANQAECgUICwABNQAFFAUIDAAgAO4dAA==.',
Nu='Nudacris:BAAANQAECggIEAABNQAECgoKKgAgAFAjAA==.Nuraga:BAABNQAECn8lAAMfAAgK8yJcBQAhAwAfAAgK8yJcBQAhAwAOAAEKcgl78wA4AAAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBQAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
Oc='Octari:BAAANQAECgEIAQAAAA==.',
Of='Ofive:BAAANQAECgIIAgABNQAECgUIEgASAAAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAABNQAECn8YAAIZAAgK6BaBNQCiAQAZAAgK6BaBNQCiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAABNQAECn8jAAIUAAkKxyC3BgArAwAUAAkKxyC3BgArAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECggIEwASAAAAAA==.Pattilicious:BAABNQAECn8UAAIDAAgK7Q3NvgCfAQADAAgK7Q3NvgCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8jAAMYAAoKZBdDFwDXAQAYAAcKhxdDFwDXAQAcAAgKXha9EwAuAQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn82AAMdAAoKJBW4DADbAQAdAAoKJBW4DADbAQADAAIK5gs9cAFuAAAAAA==.',
Pr='Protsucks:BAAANQAECgYIBgAAAA==.',
Py='Pyrug:BAAANQADCgYICwABNQAECgoKKgAaALkWAA==.',
['Pá']='Pád:BAAANQAECgQIBwABNQAECgoKMgAgAH8QAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rannmagnison:BAABNQAECn8iAAIDAAgKuwYx6QBJAQADAAgKuwYx6QBJAQAAAA==.Raquoon:BAABNQAECn8XAAIfAAUK/gpBLgDDAAAfAAUK/gpBLgDDAAAAAA==.Razzalghoul:BAABNQAECn8ZAAMHAAgK9hEOPwDOAQAHAAgK9hEOPwDOAQAGAAQKEQd2qgChAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECgUIEgASAAAAAA==.Reuli:BAAANQAECgQIBwAAAA==.Reze:BAABNQAECn8hAAIVAAoKMSN9DgD4AgAVAAoKMSN9DgD4AgABNQAFFAkJMAAIAKwkAA==.',
Rh='Rhaeynera:BAABNQAECn8aAAIYAAYKmQTEKADpAAAYAAYKmQTEKADpAAAAAA==.Rhialle:BAAANQADCgIIAgABNQAECgEIAgASAAAAAA==.Rhinne:BAAANQAECgEIAQAAAA==.',
Ri='Riezen:BAABNQAECn8nAAIGAAcKgxa4KgAqAQAGAAcKgxa4KgAqAQAAAA==.Rinorik:BAABNQAECn8hAAMLAAcK0x4JbwASAgALAAYKnh4JbwASAgAaAAIK3B+/QwC2AAAAAA==.',
Ro='Rockbiter:BAAANQAECgIIAgAAAA==.Rockhhard:BAAANQAECgMIBAAAAA==.Roeken:BAABNQAECn8rAAIOAAkK3hF7VQCCAQAOAAkK3hF7VQCCAQAAAA==.Rollingman:BAAANQAECgYICgAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8lAAIFAAoKEiCbFQAAAwAFAAoKEiCbFQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECn8gAAIZAAkKlyASEwDJAgAZAAkKlyASEwDJAgAAAA==.',
Sa='Samsó:BAABNQAECn8xAAMMAAoK8hVNHwBLAgAMAAoK8hVNHwBLAgADAAEKAACoowE1AAAAAA==.Sapharina:BAABNQAECn8zAAIBAAoKeBcpLAAVAgABAAoKeBcpLAAVAgAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8mAAQbAAoKciC1CADHAgAbAAoKciC1CADHAgATAAYKwBl5LAC4AQAWAAIKUg22UABgAAAAAA==.Schreckstoff:BAABNQAECn8oAAINAAgKmBQLXQALAgANAAgKmBQLXQALAgAAAA==.',
Se='Searfang:BAABNQAECn8sAAINAAoKMxrbPgB6AgANAAoKMxrbPgB6AgAAAA==.Sematic:BAAANQAECggIEQABNQAFFAcIGwAOAL0dAA==.Septik:BAAANQAECgEIAQAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAwAAAA==.Shamor:BAAANQAECgUICgAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA2HVQCCAQAEAAcKvA2HVQCCAQAAAA==.Shlum:BAAANQAECgEIAQAAAA==.',
Si='Silaslunark:BAABNQAECn8oAAIbAAoKzRU7DwAdAgAbAAoKzRU7DwAdAgAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skytec:BAAANQAECgMIAgAAAA==.Skëëts:BAAANQAECgIIAgAAAA==.',
Sl='Slampoof:BAAANQAECgEIAgAAAA==.Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBQAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBQASAAAAAA==.Smashmaster:BAAANQAECgQIDQAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIEQASAAAAAA==.',
Sn='Snowscayia:BAABNQAECn9oAAMTAAoKWiGMBgBaAwATAAoKWiGMBgBaAwAEAAgK4xVHNgA5AgAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBziIQC/AgAEAAkKbBziIQC/AgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8hAAIPAAcKRRxKCwAOAgAPAAcKRRxKCwAOAgAAAA==.',
Sq='Squadie:BAABNQAECn8mAAIgAAkKlApzjQDvAQAgAAkKlApzjQDvAQAAAA==.Squanchs:BAACNQAFFH8LAAICAAMKCyTICwAnAQACAAMKCyTICwAnAQA1AAQKfyoAAgIACgojJeADAKwDAAIACgojJeADAKwDAAE1AAQKBggIABIAAAAA.Squanchy:BAAANQAECgYICAAAAA==.',
Sr='Srry:BAAANQAECgcICQAAAA==.',
St='Stoot:BAAANQAECgMIBQABNQAECgUIBwASAAAAAA==.Story:BAAANQADCgUIEAAAAA==.Styrcius:BAABNQAECn8xAAIdAAkKrRytCAA7AgAdAAkKrRytCAA7AgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECggIEwAAAA==.Suniah:BAABNQAECn8UAAMfAAcKPAgMJQAdAQAfAAcKnQcMJQAdAQAOAAYKvgZ95wAWAQAAAA==.Surmise:BAAANQAECgEIAQABNQAFFAcIGwAOAL0dAA==.Sustmage:BAAANQAECgIIAgABNQAFFAcIGwAOAL0dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQAECgIIAgAAAA==.Süß:BAAANQADCgIIAgABNQAECgoKJgAbAHIgAA==.',
Ta='Tabius:BAABNQAECn8UAAIbAAYKKBnXEwC/AQAbAAYKKBnXEwC/AQAAAA==.Talkingtaco:BAAANQAECgIICAAAAA==.Taln:BAAANQAECgEIAQABNQAECgkJGgAHAKYWAA==.',
Te='Tealle:BAAANQAECgEIAQABNQAECgYIGgAcAJgQAA==.Teddumby:BAAANQADCgcICAABNQAECgcIDwASAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAABNQAECn8VAAIDAAYKkQxEzQDHAAADAAYKkQxEzQDHAAAAAA==.',
Th='Thelorìn:BAABNQAECn8hAAIWAAkK8BsoDQCUAgAWAAkK8BsoDQCUAgAAAA==.Thiccdiq:BAABNQAECn8mAAMeAAkKBBs8CwBZAgAeAAcKBh88CwBZAgAVAAQKFA7nJgDtAAAAAA==.Thiccgirl:BAAANQAECgEIAQAAAA==.Thirstycow:BAABNQAECn8aAAMCAAkKNQWvoAA1AQACAAkKNQWvoAA1AQANAAcKoAIpxwAEAQAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thornmar:BAAANQAECgQIDgAAAA==.Thosen:BAAANQAECgYICAAAAA==.',
Ti='Tinytina:BAAANQAECgQJBQAAAA==.',
To='Tore:BAABNQAECn9JAAIgAAoKHyTtBQAxAwAgAAoKHyTtBQAxAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAACNQAFFH8MAAIEAAUKPglKDgC7AAAEAAUKPglKDgC7AAA1AAQKfy0AAgQACgoYHFAeANgCAAQACgoYHFAeANgCAAAA.Tråitors:BAABNQAECn8iAAILAAgKgxE6dAASAQALAAgKgxE6dAASAQAAAA==.',
Ts='Tsarevich:BAABNQAECn8aAAIQAAUKFQeJVQECAQAQAAUKFQeJVQECAQAAAA==.',
Tw='Twileaf:BAABNQAECn8bAAITAAYKAgnTRgD7AAATAAYKAgnTRgD7AAAAAA==.',
['Té']='Térror:BAAANQADCgIIAgAAAA==.',
Ul='Ully:BAABNQAECn8SAAIRAAYK+Rb0GADXAQARAAYK+Rb0GADXAQAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIGAAgKIhMCWQCsAQAGAAgKIhMCWQCsAQAAAA==.Unug:BAAANQADCggIDgABNQAECgoKKgAaALkWAA==.',
Ut='Uthmansur:BAABNQAECn8cAAIlAAgK/AWNEQDSAAAlAAgK/AWNEQDSAAAAAA==.',
Va='Varkbyte:BAABNQAECn8dAAMBAAYKHBLwXwA4AQABAAYKHBLwXwA4AQAiAAEKAAB7WwAAAAAAAA==.Varrik:BAABNQAECn8tAAMOAAgKsR8YUACZAgAOAAgKsR8YUACZAgAlAAEK0R3NMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8mAAMBAAoKEhj9GwB/AgABAAoKEhj9GwB/AgAhAAcKRA8QBQA+AQAAAA==.Volklin:BAAANQAECgcIEQAAAA==.Voyageurs:BAABNQAECn8lAAIbAAoKFx1EBwDuAgAbAAoKFx1EBwDuAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggICgASAAAAAA==.Vyrka:BAABNQAECn8aAAIgAAYKuAnsqQDaAAAgAAYKuAnsqQDaAAAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBwABNQAECgoKMwAPABEbAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcIDwAAAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgUIDQAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBwABNQAECggIIgALAIMRAA==.Wheredergo:BAAANQAECgEIAgABNQAECgcIDwASAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Wiindsslashh:BAAANQAECgQIAwAAAA==.Windslash:BAAANQAECgEIAQAAAA==.Windsslashh:BAAANQAECgEIAQAAAA==.Wish:BAABNQAECn8lAAMYAAkK5xQ/CgBLAQAYAAgKBRY/CgBLAQAXAAYKahN5DwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECgkJHAABAIAhAA==.Wonyoung:BAABNQAECn8cAAMBAAkKgCFPKADIAgABAAkKgCFPKADIAgAiAAEKsRKJQwA+AAAAAA==.',
Wr='Wraithwok:BAAANQAECgQIBAAAAA==.',
Wu='Wuthrad:BAAANQAECgcIEgAAAA==.',
Wy='Wyze:BAAANQAECgEIAQAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQAECgEIAgAAAA==.',
Xe='Xelienn:BAABNQAECn8oAAMHAAoKKx2IIgB6AgAHAAoKKx2IIgB6AgAGAAIKMAPW0wBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAABNQAECn8qAAIBAAoKKhnyHgBpAgABAAoKKhnyHgBpAgAAAA==.Xilhaunt:BAABNQAECn88AAQaAAoKuxurBQC6AgAaAAkKkxirBQC6AgALAAoKeRnwIgAuAgAkAAQKShSnFQDwAAAAAA==.',
Xo='Xoilbiis:BAAANQAECgEIAQAAAA==.Xoilkick:BAAANQAECggIEgAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQAECggIEgAAAA==.Xorm:BAAANQAECggICgAAAA==.',
['Xê']='Xêna:BAAANQAECgUIDgAAAA==.',
['Xì']='Xì:BAAANQAECgEIAQAAAA==.',
Yb='Yb:BAAANQAECgYIDQABNQAECgoKRQAZADcgAA==.',
Ye='Yellowsnøw:BAAANQAECgUIBQAAAA==.Yenfina:BAAANQAECgEIAQAAAA==.',
Yu='Yumeshade:BAAANQAECggIDQABNQAFFAUIDAACABsRAA==.',
Za='Zaak:BAABNQAECn8xAAImAAoKGSVbAABPAwAmAAoKGSVbAABPAwAAAA==.Zamari:BAABNQAECn8UAAINAAYK7wEAlgByAAANAAYK7wEAlgByAAAAAA==.Zanzabar:BAABNQAECn8XAAIbAAkKWA22DgBBAQAbAAkKWA22DgBBAQAAAA==.',
Ze='Zelfie:BAAANQAECgIIBAAAAA==.Zeliek:BAABNQAECn86AAIMAAoKFh2pFACgAgAMAAoKFh2pFACgAgAAAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.Zeus:BAAANQADCgIIAQAAAA==.',
Zo='Zoerina:BAABNQAECn8ZAAILAAoK5w2pOQDDAQALAAoK5w2pOQDDAQAAAA==.Zoobilong:BAABNQAECn8mAAIDAAoK+hB9ggAjAgADAAoK+hB9ggAjAgAAAA==.',
Zx='Zxak:BAAANQAECgQIBAABNQAECgoKMQAmABklAA==.',
['Zë']='Zën:BAABNQAECn83AAMQAAoKeg0QRwDdAQAQAAoKeg0QRwDdAQAPAAEKCQ8xTQAsAAAAAA==.',
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
