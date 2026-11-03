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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Druid-Feral','Evoker-Preservation','Warrior-Fury','Paladin-Protection','Monk-Brewmaster','Warrior-Protection','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Warlock-Affliction','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQADCgYIBwAAAA==.',
Ae='Aeliar:BAAANQAECgIIAgAAAA==.Aenimal:BAAANQAECgQICAAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECgoKPAABAHgXAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQADCgEIAQAAAA==.',
Am='Amberlie:BAAANQAECggIDQAAAA==.Aminni:BAABNQAECn8gAAICAAgKVxHcZQDbAQACAAgKVxHcZQDbAQAAAA==.Amorgal:BAAANQAECggICAAAAA==.Amorir:BAABNQAECn8zAAIDAAoKvhYISwAUAgADAAoKvhYISwAUAgAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAABNQAECn8hAAIEAAkKsQ8sSQDEAQAEAAkKsQ8sSQDEAQAAAA==.Andeddo:BAACNQAFFH8JAAMFAAMKYw25FACcAAAFAAMKCQq5FACcAAAGAAEKWRZ3HgBTAAA1AAQKfzkABAYACgqaHdsZAPICAAYACQo7HdsZAPICAAcACAocFIk/AMsBAAUABAr5GFhBABABAAAA.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAABNQAECn8kAAIEAAoKPB0oEwBbAgAEAAoKPB0oEwBbAgAAAA==.Aregon:BAAANQADCgQIBAAAAA==.Ariodecay:BAAANQAECgUIBgAAAA==.Ariodh:BAACNQAFFH8aAAMIAAcKmCObBAAgAgAIAAYKyiWbBAAgAgAJAAYKHBhjAwBBAQA1AAQKf0YABAgACgqkJpgCAMwDAAgACgpiJpgCAMwDAAkACQrMJNUFAO0CAAoABgqeJlgFADMCAAAA.Arkaline:BAAANQADCgMIBAAAAA==.Arkham:BAAANQAECgMIBAAAAA==.Arnak:BAAANQADCgMIBAAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8PAAILAAUKABOfGwAaAQALAAUKABOfGwAaAQA1AAQKfzUAAgsACgovHuVBAIwCAAsACgovHuVBAIwCAAAA.',
At='Athenà:BAAANQADCgEIAQAAAA==.Atonedaka:BAAANQAECgIIAQABNQAECgoKJwAMAC8hAA==.',
Av='Avye:BAABNQAECn8tAAMNAAkKlBj0NQDFAQANAAkKlBj0NQDFAQACAAEKSgbtLQEhAAAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgcIDgAAAA==.Banthr:BAABNQAECn8bAAIOAAoK5g3NpADBAQAOAAoK5g3NpADBAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAgAAAA==.Beeps:BAAANQAECgUIBQAAAA==.Benchedwin:BAAANQAECgcIBgAAAA==.',
Bi='Bigcow:BAABNQAECn8UAAINAAcKnhHNgQCgAQANAAcKnhHNgQCgAQAAAA==.Bigdeeps:BAABNQAECn8oAAIOAAoKASP0GwBIAwAOAAoKASP0GwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn84AAIBAAkKyCKZCwBkAwABAAkKyCKZCwBkAwAAAA==.Blacksmage:BAAANQADCgEIAQAAAA==.Blastcannon:BAABNQAECn8gAAMPAAgKowMTHgD8AAAPAAcK1wMTHgD8AAAQAAQK5QGhrwFiAAAAAA==.Bluejuly:BAAANQADCgEIAQAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bormass:BAAANQADCgEIAQAAAA==.Bowwie:BAAANQADCgUIBwABNQAFFAQICgARAPESAA==.',
Br='Brackish:BAAANQADCgEIAQAAAA==.Bravehearth:BAABNQAECn8XAAIDAAoK8A5VYwDPAQADAAoK8A5VYwDPAQABNQAECgUIBQASAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8rAAMEAAkKrxLCJwCHAQAEAAkKrxLCJwCHAQATAAEKmgD8eAAMAAAAAA==.Bulan:BAABNQAECn8wAAIUAAkK1SMlBgA5AwAUAAkK1SMlBgA5AwAAAA==.',
Ca='Candypants:BAABNQAECn8yAAMUAAoKFBjCDgDqAQAUAAoKFBjCDgDqAQAVAAEKMgeEUwAzAAAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECn8vAAIPAAoKPiF9AwANAwAPAAoKPiF9AwANAwAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAABNQAECn8VAAIWAAYK7AI6OgCOAAAWAAYK7AI6OgCOAAAAAA==.Cayssaris:BAABNQAECn8ZAAIXAAYKvh7IHQBaAQAXAAYKvh7IHQBaAQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn84AAMYAAoKLhx+BAC/AgAYAAoK2Rt+BAC/AgAZAAYKNRsxGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgMIAwABNQAECgkJHQABAIAhAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chappedlips:BAAANQAECggIEQAAAA==.Cheetor:BAAANQAECggICQABNQAECgoKTgAWAKghAA==.Chelthud:BAAANQADCgEIAQAAAA==.Chidaka:BAAANQAECgEIAgABNQAECgoKJwAMAC8hAA==.Chilia:BAAANQADCgEIAQAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAACNQAFFH8JAAILAAUKLBJeEwDhAAALAAUKLBJeEwDhAAA1AAQKfysAAwsACgqxGHctACwCAAsACgqxGHctACwCABoABQqBDas3AOIAAAAA.Cosairi:BAABNQAECn8eAAICAAgKmBbqggCDAQACAAgKmBbqggCDAQAAAA==.Cougztroll:BAABNQAECn8qAAMXAAoKQBPxGwBqAQAXAAkKFBPxGwBqAQAbAAEKeBQYPAA0AAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8gAAIRAAkKHyM0BwCSAgARAAkKHyM0BwCSAgAAAA==.Crossie:BAAANQADCgEIAwAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgoKOAAYAC4cAA==.',
Cu='Cuttercupx:BAAANQAECgUICgABNQAECgcIDQASAAAAAA==.',
Da='Dahn:BAAANQAECggIDgABNQAECgoKTgAWAKghAA==.Dakadin:BAABNQAECn8nAAIMAAoKLyGvJADYAgAMAAoKLyGvJADYAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn83AAIDAAoKEBoRVACZAgADAAoKEBoRVACZAgAAAA==.Darkenedstar:BAAANQAECgIIAgABNQAECgQICAASAAAAAA==.Darkkor:BAAANQADCgEIAQAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn9PAAMFAAkK4A/dNgBAAQAFAAgK3xHdNgBAAQAHAAEK5QMOpgAoAAAAAA==.Dashy:BAAANQAECgUIBQAAAA==.Dawnstone:BAAANQAECgQIDAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn8zAAMaAAoKuxjMAgD5AQALAAoKCBZaOAD/AQAaAAgKMBfMAgD5AQAAAA==.Deafsmash:BAAANQAECgIIBAABNQAECgkJMAAGAO4dAA==.Delamyr:BAAANQADCgEIAQABNQADCgYICAASAAAAAA==.Delina:BAAANQADCgYIBwAAAA==.Delusional:BAAANQAECgEIAQAAAA==.Denaric:BAAANQAECgUIBAABNQAECgkJIQAcAH8MAA==.Destroyevsky:BAABNQAECn8XAAIdAAYKJQM1IgBhAAAdAAYKJQM1IgBhAAAAAA==.Detonate:BAAANQAECggICAAAAA==.',
Di='Digem:BAAANQADCgEIAgABNQADCgcIEwASAAAAAA==.Dixinu:BAAANQAECgQIBgAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhn+FwDoAAADAAMKPhn+FwDoAAAeAAIKYwrbDgBYAAA1AAQKfyYAAwMACQpgI3kdAE0DAAMACQpgI3kdAE0DAB4ABAo7GXpAAPcAAAAA.Dotsonyourpp:BAAANQADCgQIBAABNQAECgoKGwAQAAkWAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJIwAUAMcgAA==.Dragonwarior:BAABNQAECn8eAAIOAAoKMA9xowDEAQAOAAoKMA9xowDEAQAAAA==.Drykkr:BAABNQAECn8UAAIfAAYKuht7FQCMAQAfAAYKuht7FQCMAQAAAA==.',
Du='Duuhh:BAAANQADCgEIAQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggIDQASAAAAAA==.Element:BAAANQADCgUIBgAAAA==.Ellipsis:BAAANQAECgEIAQAAAA==.Elpollo:BAABNQAECn8bAAIQAAoKCRZOQgAhAgAQAAoKCRZOQgAhAgAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgoKKAADAEESAA==.',
Ep='Epitome:BAABNQAECn8zAAMPAAoKNh0LBQBbAgAPAAoKNh0LBQBbAgAQAAIKegJqyQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.Erolatha:BAAANQAECgEIAQAAAA==.',
Et='Ethereal:BAAANQADCgIIAgAAAA==.Etude:BAAANQAECgQIBwABNQAFFAYIDQACAPEOAA==.',
Eu='Eunha:BAABNQAECn8XAAIUAAkKQhtpCgBgAgAUAAkKQhtpCgBgAgABNQAECgkJHQABAIAhAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgkJTwAFAOAPAA==.Evergrey:BAAANQAECgQIDAAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQAECgUIBAAAAA==.Falasdaer:BAAANQAECgUICQAAAA==.Falstaff:BAAANQADCgcIDwAAAA==.Fastor:BAAANQADCggICAAAAA==.Fatalis:BAAANQADCggIIQAAAA==.Fatterblunt:BAACNQAFFH8WAAIEAAcKRgxaBwBiAQAEAAcKRgxaBwBiAQA1AAQKfzoAAgQACgrgHAURAHkCAAQACgrgHAURAHkCAAAA.',
Fe='Feldar:BAABNQAECn8sAAIDAAoK3BzXXQB/AgADAAoK3BzXXQB/AgAAAA==.Felmoore:BAAANQAECgQIBAAAAA==.Feronite:BAACNQAFFH8KAAIRAAQK8RJpAwDbAAARAAQK8RJpAwDbAAA1AAQKfz8AAhEACgoYIOcGABQDABEACgoYIOcGABQDAAAA.',
Fi='Fizzleclaw:BAABNQAECn8kAAMEAAoKXBgHHwDTAQAEAAkKvRIHHwDTAQAXAAcKghzZHQBaAQAAAA==.Fizzleded:BAAANQADCgIIAwABNQAECgoKJAAEAFwYAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlelord:BAAANQAECgIIAgAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fl='Fluchtweg:BAAANQAECggIDgABNQAECgoKLAAbAHIgAA==.',
Fo='Fordi:BAAANQADCggIHgAAAA==.Fourdy:BAABNQAECn8VAAICAAkKZxPGVQCKAQACAAkKZxPGVQCKAQAAAA==.',
Fr='Fredwin:BAABNQAECn8UAAILAAgKYQuusABvAQALAAgKYQuusABvAQAAAA==.Free:BAAANQAECgMIAwABNQAECgQIBAASAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJFAABNQAECgQIBAASAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Galicos:BAAANQAECgYICAAAAA==.Ganthex:BAAANQADCgUIBQAAAA==.Gapper:BAABNQAECn9OAAIWAAoKqCEyCQBAAwAWAAoKqCEyCQBAAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAgALwgAA==.Gargodath:BAAANQADCgEIAQAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICQAAAA==.Glestaar:BAABNQAECn8uAAIhAAoKah72HQCjAgAhAAoKah72HQCjAgAAAA==.Glitterpants:BAAANQAECgcIBQAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8gAAIOAAkKlxURfgAgAgAOAAkKlxURfgAgAgAAAA==.',
Go='Gojira:BAABNQAECn8dAAIMAAYKVx44NwAKAgAMAAYKVx44NwAKAgAAAA==.Golgaria:BAAANQADCgEIAQAAAA==.Gothri:BAABNQAECn8jAAMUAAkK/BgDEwBNAgAUAAkK/BgDEwBNAgAVAAEKCA+KbAAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIDwASAAAAAA==.Grollosh:BAAANQADCgEIAQAAAA==.Grymwarr:BAABNQAECn8mAAIOAAoKABKtSQDyAQAOAAoKABKtSQDyAQAAAA==.',
Ha='Haerin:BAAANQAECgYIDAABNQAECgkJHQABAIAhAA==.Hakoa:BAAANQADCgIIAgAAAA==.Harnel:BAABNQAECn8iAAIDAAYKNgQnHwHrAAADAAYKNgQnHwHrAAAAAA==.Hattorihanzo:BAAANQADCgUICAAAAA==.',
He='Healmart:BAAANQAECgcICgAAAA==.Hellborne:BAAANQABCgIIAgABNQAECgQICAASAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQASAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQAECgUIBQAAAA==.',
In='Ingraver:BAAANQADCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAFFAQICgARAPESAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgUIBgAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAABNQAECn8aAAIQAAoKrB3zNAAgAwAQAAoKrB3zNAAgAwAAAA==.Kaliel:BAAANQADCggIHAAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgYIBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwALAEsRAA==.',
Ke='Kentukee:BAAANQADCgEIAQABNQAECgkJKgANAKwUAA==.Kernelpanic:BAACNQAFFH8WAAQGAAYK7R4ZAgBgAQAGAAUKRh4ZAgBgAQAHAAIKZBmZFACZAAAFAAIKAAAlNgAnAAA1AAQKfy8AAwYACgopIqcPAF0CAAYACQpaIacPAF0CAAcABArpF7p0AJgAAAAA.Keyoshi:BAAANQAECggIDgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICgAAAA==.Kilrinstinct:BAAANQADCgYIDwAAAA==.Kirkle:BAABNQAECn9DAAIaAAoKTxvHAQBdAgAaAAoKTxvHAQBdAgAAAA==.',
Ko='Korlas:BAAANQADCgEIAQAAAA==.Kovie:BAAANQAECgIIAgAAAA==.Kovis:BAAANQADCgEIAQAAAA==.Kovy:BAAANQADCgYIDQAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwALAEsRAA==.',
Ku='Kulrath:BAAANQAECggIDQAAAA==.',
Kw='Kwovie:BAABNQAECn8eAAIXAAkK4BneEABTAgAXAAkK4BneEABTAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8lAAIDAAgKohBCqgDLAQADAAgKohBCqgDLAQAAAA==.Landrick:BAAANQAECgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgYICgABNQAECgcIFAAZAHcPAA==.Lavasaurus:BAABNQAECn8UAAIZAAcKdw+pEgDcAAAZAAcKdw+pEgDcAAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAABNQAECn8WAAMhAAkKLguv4AA/AQAhAAgKugyv4AA/AQAWAAMKBwKBbAB8AAAAAA==.',
Li='Lifebloomz:BAABNQAECn8pAAMTAAgKMhQgJACGAQATAAgKMhQgJACGAQAXAAUKEQNERwBwAAAAAA==.Lilfluffcc:BAABNQAECn8gAAIRAAoKJxF1EQBSAgARAAoKJxF1EQBSAgAAAA==.',
Lo='Lockward:BAABNQAECn8uAAMLAAoKKxrCNQAKAgALAAoKmxjCNQAKAgAaAAEK9BaXKQBIAAAAAA==.Lorblor:BAABNQAECn8iAAIIAAkK4hq4IADKAQAIAAkK4hq4IADKAQAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8qAAINAAkK5RZuVgAgAgANAAkK5RZuVgAgAgAAAA==.Lunafox:BAABNQAECn8nAAMCAAoK9xarJQBoAgACAAoK9xarJQBoAgANAAcK+AmHaQAQAQAAAA==.Lunamae:BAABNQAECn8fAAIQAAkKDA7SzgDoAQAQAAkKDA7SzgDoAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgoKRQABAKYcAA==.Luvvyyaa:BAABNQAECn9FAAQBAAoKphzTPgBvAgABAAoKphzTPgBvAgAiAAIKwQp8IABeAAAjAAEKdwnbVAA2AAAAAA==.Luvyya:BAAANQAECggICwABNQAECgoKRQABAKYcAA==.',
Ly='Lythomancer:BAABNQAECn8fAAIaAAkK4QcAIQBpAQAaAAkK4QcAIQBpAQAAAA==.',
Ma='Maddeena:BAAANQAECgcIEgAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAILAAUKSxGYEQBzAQALAAUKSxGYEQBzAQA1AAQKfzEAAgsACQpUIq8ZACADAAsACQpUIq8ZACADAAAA.',
Mc='Mcmercie:BAABNQAECn8oAAMeAAoKMQ+cGgBmAQAeAAoKMQ+cGgBmAQADAAEKAAAMrgEAAAAAAA==.',
Me='Mechacooter:BAABNQAECn8pAAIkAAoKSRjjGwCfAgAkAAoKSRjjGwCfAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8pAAIQAAgKHBKcewCFAQAQAAgKHBKcewCFAQAAAA==.Melchiorr:BAACNQAFFH8GAAIlAAIK2RDHAwCZAAAlAAIK2RDHAwCZAAA1AAQKfz0AAiUACgqoG5ICAPQCACUACgqoG5ICAPQCAAAA.Melynne:BAABNQAECn8qAAICAAoK6BMFMAAvAgACAAoK6BMFMAAvAgAAAA==.',
Mi='Miku:BAEANQADCgYIDAABNQAECgkJJgADAAQkAA==.Minji:BAABNQAECn8XAAIlAAgK1BlNCQDvAQAlAAgK1BlNCQDvAQABNQAECgkJHQABAIAhAA==.Minsoo:BAACNQAFFH8GAAIUAAIK8hgeBwCcAAAUAAIK8hgeBwCcAAA1AAQKfzcAAhQACgpSIX0CAKwDABQACgpSIX0CAKwDAAAA.',
Ml='Mlrgl:BAABNQAECn8qAAMhAAoKUCMbNQBCAgAhAAoKUCMbNQBCAgAWAAUK0xJ3RgAnAQAAAA==.Mlrglet:BAAANQAECggICQABNQAECgoKKgAhAFAjAA==.Mlrglo:BAAANQAECgUJBgABNQAECgoKKgAhAFAjAA==.',
Mo='Mon:BAAANQADCgEIAQAAAA==.Mootzarell:BAAANQADCgEIAQAAAA==.Mormegil:BAABNQAECn8eAAQHAAoKrhaxJAD0AQAHAAoKPxOxJAD0AQAFAAUKbhnYagBIAQAGAAMKIx2kjADyAAAAAA==.Moshimoshi:BAACNQAFFH8NAAMCAAYK8Q6KDQA9AQACAAUKjguKDQA9AQANAAEKAADAKwAAAAA1AAQKfx0AAwIACgpcFcxKADgCAAIACgpcFcxKADgCAA0AAwo6FTOnAIYAAAAA.Motosake:BAAANQADCgUIBQABNQAFFAYIDQACAPEOAA==.',
Mt='Mtx:BAAANQAECgQIBgAAAA==.',
Mu='Muriana:BAAANQADCgYICQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAABNQAECn8hAAQcAAkKfwwnMQASAQAcAAYKgg8nMQASAQAYAAUKkA1WDQDiAAAZAAUKmRHxFAC5AAAAAA==.Nagashunters:BAAANQADCgMIBAAAAA==.Najuma:BAAANQADCgIIAwAAAA==.',
Nb='Nbg:BAAANQAECggIEQABNQAECgoKKQAkAEkYAA==.',
Ne='Nessará:BAABNQAECn86AAIBAAoKRRRZLABgAgABAAoKRRRZLABgAgAAAA==.Newgate:BAAANQAECgQIAwAAAA==.',
Ni='Nightgodjuju:BAABNQAECn8pAAMPAAoKvRDnCADcAQAPAAoKvRDnCADcAQAQAAEKXwIJTgErAAAAAA==.Nikna:BAAANQAECgUICwABNQAFFAUIDgAhAO4dAA==.',
Nu='Nudacris:BAAANQAECggIDwABNQAECgoKKgAhAFAjAA==.Nuraga:BAABNQAECn8oAAMgAAgKPCNcBQAhAwAgAAgKPCNcBQAhAwAOAAEKcgn9DQE3AAAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
Of='Ofive:BAAANQADCgEIAQABNQAECggIFAAbAOoLAA==.',
On='Onarius:BAAANQADCgIIAwAAAA==.Onazix:BAABNQAECn8ZAAIWAAgK6BaBNQCiAQAWAAgK6BaBNQCiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgcIDQAAAA==.Pandakyle:BAABNQAECn8jAAIUAAkKxyC3BgArAwAUAAkKxyC3BgArAwAAAA==.Patchmen:BAAANQADCgcICAAAAA==.Patootie:BAAANQADCgEIAQABNQAECggIEAASAAAAAA==.Pattilicious:BAABNQAECn8UAAIDAAgK7Q3NvgCfAQADAAgK7Q3NvgCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8jAAMZAAoKZBdDFwDXAQAZAAcKhxdDFwDXAQAcAAgKXhbwGAAqAQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn88AAMeAAoKUBeDDgAMAgAeAAoKUBeDDgAMAgADAAIK5gs9cAFuAAAAAA==.',
Pr='Protsucks:BAAANQAECgYIBgAAAA==.',
Py='Pyrug:BAAANQADCgYIDAABNQAECgoKMwAaALsYAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgoKOAAhAFwSAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rankak:BAAANQAECgIIAgABNQAFFAIIBgAUAPIYAA==.Rannmagnison:BAABNQAECn8oAAIDAAgKuwYx6QBJAQADAAgKuwYx6QBJAQAAAA==.Raquoon:BAABNQAECn8cAAIgAAYKcQrgIwCnAAAgAAYKcQrgIwCnAAAAAA==.Razzalghoul:BAABNQAECn8bAAMHAAgK9hEOPwDOAQAHAAgK9hEOPwDOAQAGAAQKEQd2qgChAAAAAA==.',
Re='Reidar:BAAANQADCgEIAQABNQAECggIFAAbAOoLAA==.Reuli:BAAANQAECgMIBgAAAA==.Reze:BAABNQAECn8nAAIVAAoKYyN9DgD4AgAVAAoKYyN9DgD4AgABNQAFFAoKNAAIABkmAA==.',
Rh='Rhaeynera:BAABNQAECn8gAAIZAAYKmQTpFwCPAAAZAAYKmQTpFwCPAAAAAA==.Rhialle:BAAANQADCgQIBgABNQAECgEIAQASAAAAAA==.Rhinne:BAAANQAECgQIBgAAAA==.',
Ri='Riezen:BAABNQAECn8qAAIGAAkK1RNhIwCUAQAGAAkK1RNhIwCUAQAAAA==.Rinorik:BAABNQAECn8pAAMLAAgKmB4MUACsAQALAAcKYh4MUACsAQAaAAIK3B+/QwC2AAAAAA==.',
Ro='Rockbiter:BAAANQAECgIIAgAAAA==.Rockhhard:BAAANQAECgMIAgAAAA==.Roeken:BAABNQAECn8vAAIOAAkKNxKoawCFAQAOAAkKNxKoawCFAQAAAA==.Rollingman:BAAANQAECgcICQAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8rAAIFAAoKoyObFQAAAwAFAAoKoyObFQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFQAAAA==.',
Ry='Rybear:BAAANQADCgcIDAAAAA==.Ryutiz:BAABNQAECn8pAAIWAAoKHyDJCgBsAgAWAAoKHyDJCgBsAgAAAA==.',
Sa='Samsó:BAABNQAECn8yAAMMAAoK8hWELgA3AgAMAAoK8hWELgA3AgADAAEKAACoowE1AAAAAA==.Sapharina:BAABNQAECn88AAMBAAoKeBcKQAABAgABAAoKeBcKQAABAgAjAAkK5Qd7GgCJAQAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8sAAQbAAoKciC1CADHAgAbAAoKciC1CADHAgATAAcK8Bd5LAC4AQAXAAIKUg22UABgAAAAAA==.Schreckstoff:BAABNQAECn8qAAINAAkKrBRpQQCUAQANAAkKrBRpQQCUAQAAAA==.',
Se='Searfang:BAACNQAFFH8HAAINAAMK8AshEADQAAANAAMK8AshEADQAAA1AAQKfy0AAg0ACgozGts+AHoCAA0ACgozGts+AHoCAAAA.Sematic:BAABNQAECn8aAAMlAAoKGyCXAgB8AgAlAAgKdSCXAgB8AgALAAYKJxnsfQAuAQABNQAFFAcIGwAOAL0dAA==.Senpai:BAAANQADCgUIBQAAAA==.Septik:BAAANQADCggJDQAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shadrielis:BAAANQAECgQIBAABNQAECgoKKgAhAFAjAA==.Shamcrusade:BAAANQADCgEIAQABNQAECgoKKgAhAFAjAA==.Shamor:BAAANQAECgYIDgAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA2HVQCCAQAEAAcKvA2HVQCCAQAAAA==.Shlum:BAAANQADCgcIFAAAAA==.',
Si='Silaslunark:BAABNQAECn8tAAIbAAoK7Ba2CwDIAQAbAAoK7Ba2CwDIAQAAAA==.',
Sk='Skooty:BAAANQADCgQIBQAAAA==.Skytec:BAAANQAECgIIAwAAAA==.Skëëts:BAAANQAECgIIAgAAAA==.',
Sl='Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAASAAAAAA==.Smashmaster:BAAANQAECgQIDQAAAA==.Smøk:BAAANQADCgQIBgABNQAECgcIDwASAAAAAA==.',
Sn='Snowscayia:BAABNQAECn9wAAMTAAoKQCKMBgBaAwATAAoKQCKMBgBaAwAEAAgK4xVHNgA5AgAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBziIQC/AgAEAAkKbBziIQC/AgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8pAAIPAAgKYBtKCwAOAgAPAAgKYBtKCwAOAgAAAA==.',
Sq='Squadie:BAABNQAECn8sAAIhAAkKtApzjQDvAQAhAAkKtApzjQDvAQAAAA==.Squanchs:BAACNQAFFH8MAAICAAQKXiQeCQCPAQACAAQKXiQeCQCPAQA1AAQKfysAAgIACgrcJeADAKwDAAIACgrcJeADAKwDAAE1AAQKBggHABIAAAAA.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgcICQAAAA==.',
St='Stoot:BAAANQAECgMIBAABNQAECgUIFAAVABwkAA==.Stormdaka:BAAANQAECgEIAQABNQAECgoKJwAMAC8hAA==.Story:BAAANQADCgUIEAAAAA==.Styrcius:BAABNQAECn8xAAIeAAkKrRznDAArAgAeAAkKrRznDAArAgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECggIEAAAAA==.Suniah:BAABNQAECn8VAAMgAAgKPwkMJQAdAQAgAAgKuwgMJQAdAQAOAAYKvgZ95wAWAQAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAcIGwAOAL0dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQAECgIIAQAAAA==.Süß:BAAANQADCgIIAwABNQAECgoKLAAbAHIgAA==.',
Ta='Tabius:BAABNQAECn8UAAIbAAYKKBnXEwC/AQAbAAYKKBnXEwC/AQAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.Taln:BAAANQABCgEIAQABNQAECgoKHgAHAK4WAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDQASAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAABNQAECn8WAAIDAAcKawtF1ADzAAADAAcKawtF1ADzAAAAAA==.',
Th='Thelorìn:BAABNQAECn8lAAIXAAkK8BsoDQCUAgAXAAkK8BsoDQCUAgAAAA==.Thiccdiq:BAABNQAECn8uAAMfAAkKQh2sBAA6AgAfAAgKXx6sBAA6AgAVAAQKFA7QLwDnAAAAAA==.Thiccgirl:BAAANQADCgEIAQAAAA==.Thirstycow:BAABNQAECn8aAAMCAAkKNQWvoAA1AQACAAkKNQWvoAA1AQANAAcKoAIpxwAEAQAAAA==.Thorkell:BAAANQADCgcIDQAAAA==.Thornmar:BAAANQAECgQIEQAAAA==.Thosen:BAAANQAECgYICwAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECn9OAAIhAAoK5SW6BgBEAwAhAAoK5SW6BgBEAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAACNQAFFH8MAAIEAAUKPgkTEgCzAAAEAAUKPgkTEgCzAAA1AAQKfy0AAgQACgoYHFAeANgCAAQACgoYHFAeANgCAAAA.Tråitors:BAABNQAECn8kAAILAAgKZhNlegA3AQALAAgKZhNlegA3AQAAAA==.',
Ts='Tsarevich:BAABNQAECn8gAAIQAAYKbweO3gDEAAAQAAYKbweO3gDEAAAAAA==.',
Tw='Twileaf:BAABNQAECn8bAAITAAYKAgnTRgD7AAATAAYKAgnTRgD7AAAAAA==.',
['Té']='Térror:BAAANQADCgIIAgAAAA==.',
Ul='Ully:BAAANQAECgYIEAAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIGAAgKIhMCWQCsAQAGAAgKIhMCWQCsAQAAAA==.Unug:BAAANQADCggIDwABNQAECgoKMwAaALsYAA==.',
Ut='Uthmansur:BAABNQAECn8jAAIdAAkKLgYPFAD1AAAdAAkKLgYPFAD1AAAAAA==.',
Va='Varkbyte:BAABNQAECn8iAAMBAAYKiRIMcgBIAQABAAYKiRIMcgBIAQAjAAEKAACdbQAAAAAAAA==.Varrik:BAABNQAECn8tAAMOAAgKsR8YUACZAgAOAAgKsR8YUACZAgAdAAEK0R3NMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBgAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8nAAMBAAoKjxjdKAB0AgABAAoKjxjdKAB0AgAiAAcKRA/QBgA4AQAAAA==.Volklin:BAABNQAECn8YAAICAAcKQAMKjgDbAAACAAcKQAMKjgDbAAAAAA==.Volyria:BAAANQADCgEIAQAAAA==.Voyageurs:BAABNQAECn8mAAIbAAoKFx1EBwDuAgAbAAoKFx1EBwDuAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggIDQASAAAAAA==.Vyrka:BAABNQAECn8gAAIhAAcK/wkBqQAbAQAhAAcK/wkBqQAbAQAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBgABNQAECgoKPAAPAMgbAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcIDwAAAA==.Werewithal:BAAANQADCgUIBQABNQAECgkJKgANAKwUAA==.Wesleypipes:BAAANQADCgEIAgAAAA==.Wetheals:BAAANQAECgYICAAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECggIJAALAGYTAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQASAAAAAA==.Wholeymilk:BAAANQADCgEIAQAAAA==.Whosurpally:BAAANQADCgUICAAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Wiindsslashh:BAAANQAECgYIBwAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Windsslashh:BAAANQAECgEIAgAAAA==.Wish:BAABNQAECn8tAAMZAAoKCxZqBwDxAQAZAAoKCxZqBwDxAQAYAAYKahN5DwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECgkJHQABAIAhAA==.Wonyoung:BAABNQAECn8dAAMBAAkKgCFPKADIAgABAAkKgCFPKADIAgAjAAEKsRJ+UAA+AAAAAA==.',
Wr='Wraithwok:BAAANQAECgQIAwAAAA==.Wråth:BAAANQAECgYIBgAAAA==.',
Wu='Wuthrad:BAAANQAECgcIEQAAAA==.',
Wy='Wyze:BAAANQAECgEIAQAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.',
Xe='Xelienn:BAABNQAECn8pAAMHAAoKKx2IIgB6AgAHAAoKKx2IIgB6AgAGAAIKMAPW0wBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGwAAAA==.',
Xi='Xia:BAABNQAECn8zAAIBAAoKMRwtGgDYAgABAAoKMRwtGgDYAgAAAA==.Xilhaunt:BAABNQAECn9FAAQaAAoKCRyrBQC6AgAaAAkKkxirBQC6AgALAAoK8BmiLQArAgAlAAQKShSnFQDwAAAAAA==.',
Xo='Xoilcast:BAAANQAECgMIAwAAAA==.Xoilkick:BAAANQAECggIDwAAAA==.Xoilpal:BAAANQADCgMIBAAAAA==.Xoilwings:BAABNQAECn8WAAMKAAgKcRFMDwAdAQAKAAcKvxNMDwAdAQAIAAEK6AWaegAqAAAAAA==.Xorm:BAAANQAECggIDwAAAA==.',
['Xê']='Xêna:BAAANQAECgUICwAAAA==.',
['Xì']='Xì:BAAANQAECgEIAQAAAA==.',
Ya='Yaktac:BAAANQADCgIIAgAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgoKTgAWAKghAA==.',
Ye='Yellowsnøw:BAAANQAECgUIBAAAAA==.Yenfina:BAAANQADCgEIAQAAAA==.',
Yu='Yumeshade:BAAANQAECgcIDQABNQAFFAYIDQACAPEOAA==.',
Za='Zaak:BAABNQAECn88AAMmAAoKkSViAABpAwAmAAoKkSViAABpAwAhAAEK3yKWCAFlAAAAAA==.Zamari:BAABNQAECn8YAAINAAYK9gGkrwB2AAANAAYK9gGkrwB2AAAAAA==.Zanzabar:BAABNQAECn8XAAIbAAkKWA2FFQAqAQAbAAkKWA2FFQAqAQAAAA==.',
Ze='Zelfie:BAAANQAECgIIAQAAAA==.Zeliek:BAABNQAECn8/AAIMAAoKFh3rIQDlAgAMAAoKFh3rIQDlAgAAAA==.Zerodarkness:BAAANQADCgQIBgAAAA==.Zerooné:BAAANQADCgYIDQAAAA==.Zeus:BAAANQADCgIIAQAAAA==.',
Zo='Zoerina:BAABNQAECn8bAAILAAoKKw4oTgCyAQALAAoKKw4oTgCyAQAAAA==.Zoobilong:BAABNQAECn8oAAIDAAoKQRJ9ggAjAgADAAoKQRJ9ggAjAgAAAA==.',
Zx='Zxak:BAAANQAECgQIAwABNQAECgoKPAAmAJElAA==.',
['Zë']='Zën:BAABNQAECn8/AAMQAAoKJA7RWADgAQAQAAoKJA7RWADgAQAPAAEKCQ8xTQAsAAAAAA==.',
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
