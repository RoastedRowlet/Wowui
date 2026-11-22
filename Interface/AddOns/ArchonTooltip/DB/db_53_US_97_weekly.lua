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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Druid-Feral','Warrior-Fury','Paladin-Protection','Monk-Brewmaster','Priest-Shadow','Warlock-Affliction','Warrior-Protection','Hunter-BeastMastery','Priest-Discipline','Rogue-Assassination','Evoker-Preservation','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQADCgYIBgAAAA==.',
Ae='Aeliar:BAAANQAECggICgAAAA==.Aenimal:BAAANQAECgQICAAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAFFAIIBQABAIMKAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Aleshock:BAAANQABCgQICAAAAA==.',
Am='Amberlie:BAABNQAECn8XAAICAAkKbQwEhACAAQACAAkKbQwEhACAAQAAAA==.Aminni:BAABNQAECn8gAAICAAgKVxHcZQDbAQACAAgKVxHcZQDbAQAAAA==.Amorgal:BAAANQAECggICAAAAA==.Amorir:BAABNQAECn83AAIDAAoKNReuXAAbAgADAAoKNReuXAAbAgAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAABNQAECn8hAAIEAAkKsQ8sSQDEAQAEAAkKsQ8sSQDEAQAAAA==.Andeddo:BAACNQAFFH8JAAMFAAMKYw3vGwCSAAAFAAMKCQrvGwCSAAAGAAEKWRZ3HgBTAAA1AAQKfzkABAYACgqaHdsZAPICAAYACQo7HdsZAPICAAcACAocFIk/AMsBAAUABAr5GBFNAAkBAAAA.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAABNQAECn8kAAIEAAoKPB22GwDrAgAEAAoKPB22GwDrAgAAAA==.Aregon:BAAANQADCgQIBAAAAA==.Ariodecay:BAAANQAECgMIBgAAAA==.Ariodh:BAACNQAFFH8dAAMIAAgKxR6bBAAgAgAIAAYKyiWbBAAgAgAJAAcKnxRmAwB2AQA1AAQKf0kABAgACgqkJpgCAMwDAAgACgpiJpgCAMwDAAkACQoMJUIHAOcCAAoABgqeJrgGADECAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBAAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8PAAILAAUKABOfGwAaAQALAAUKABOfGwAaAQA1AAQKfzYAAgsACgovHuVBAIwCAAsACgovHuVBAIwCAAAA.',
At='Athenà:BAAANQABCgYICQAAAA==.Atonedaka:BAAANQAECgIIAQABNQAECgoKLAAMAC8hAA==.',
Av='Avye:BAABNQAECn8wAAMNAAkKlBjeRgC5AQANAAkKlBjeRgC5AQACAAEKSgbtLQEhAAAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgcIDwAAAA==.Banthr:BAABNQAECn8bAAIOAAoK5g3NpADBAQAOAAoK5g3NpADBAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Beeps:BAAANQAECgUIBQAAAA==.Benchedwin:BAAANQAECgcIBgAAAA==.',
Bi='Bigcow:BAABNQAECn8UAAINAAcKnhHNgQCgAQANAAcKnhHNgQCgAQAAAA==.Bigdeeps:BAABNQAECn8oAAIOAAoKASP0GwBIAwAOAAoKASP0GwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn86AAIBAAkKNSMhDwBjAwABAAkKNSMhDwBjAwAAAA==.Blastcannon:BAABNQAECn8gAAMPAAgKowMTHgD8AAAPAAcK1wMTHgD8AAAQAAQK5QGhrwFiAAAAAA==.Bluejuly:BAAANQABCgYICQAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAFFAQICgARAPESAA==.',
Br='Bravehearth:BAABNQAECn8bAAIDAAoKVRCKdgDhAQADAAoKVRCKdgDhAQABNQAECgcIDAASAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8rAAMEAAkKrxJOMACFAQAEAAkKrxJOMACFAQATAAEKmgDBigAMAAAAAA==.Bulan:BAABNQAECn84AAIUAAkK9iOsBABjAwAUAAkK9iOsBABjAwAAAA==.',
Ca='Candypants:BAABNQAECn8yAAMUAAoKFBjRFQAeAgAUAAoKFBjRFQAeAgAVAAEKMgf0XgAxAAAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECn85AAIPAAoKOyJ9AwANAwAPAAoKOyJ9AwANAwAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAABNQAECn8VAAIWAAYK7AKFRACMAAAWAAYK7AKFRACMAAAAAA==.Cayssaris:BAABNQAECn8ZAAIXAAYKvh5DJgBTAQAXAAYKvh5DJgBTAQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn84AAMYAAoKLhx+BAC/AgAYAAoK2Rt+BAC/AgAZAAYKNRsxGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgMIAwABNQAECgkJHQABAIAhAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chappedlips:BAAANQAECggIEQAAAA==.Cheetor:BAAANQAECggICQABNQAECgoKWAAWALYhAA==.Chidaka:BAAANQAECgEIAgABNQAECgoKLAAMAC8hAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAACNQAFFH8JAAILAAUKLBIoGwDWAAALAAUKLBIoGwDWAAA1AAQKfywAAwsACgqxGKQ9AB4CAAsACgqxGKQ9AB4CABoABQqBDas3AOIAAAAA.Cosairi:BAABNQAECn8jAAICAAoKcRO+aAB7AQACAAoKcRO+aAB7AQAAAA==.Cougztroll:BAABNQAECn8uAAMXAAoKoxNMHgCRAQAXAAoK6hJMHgCRAQAbAAEKeBTzPgA+AAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8hAAIRAAkKHyNzCQCJAgARAAkKHyNzCQCJAgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgoKOAAYAC4cAA==.',
Cu='Cuttercupx:BAAANQAECgUICgABNQAECgcIDQASAAAAAA==.',
Da='Dahn:BAABNQAECn8YAAIHAAkKCRfnIABHAgAHAAkKCRfnIABHAgABNQAECgoKWAAWALYhAA==.Dakadin:BAABNQAECn8sAAIMAAoKLyGvJADYAgAMAAoKLyGvJADYAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn9BAAIDAAoKXhoRVACZAgADAAoKXhoRVACZAgAAAA==.Darkenedstar:BAAANQAECgIIAgABNQAECgQICAASAAAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn9TAAMFAAkK4A8VQgA1AQAFAAgK3xEVQgA1AQAHAAQKdwS8lAB1AAAAAA==.Dashy:BAAANQAECgUIBQAAAA==.Dawnstone:BAAANQAECgQIDAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn83AAMaAAoKrRpkAwARAgAaAAgKvRhkAwARAgALAAoKvRZfRQAEAgAAAA==.Deafsmash:BAAANQAECgIIBAABNQAECgkJMgAGACYeAA==.Delamyr:BAAANQABCgIIAwABNQADCgYIBgASAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Delusional:BAAANQAECgEIAQAAAA==.Denaric:BAAANQAECgQIBAABNQAECgkJJAAYAOYVAA==.Destroyevsky:BAABNQAECn8hAAIcAAcK4AOAJACEAAAcAAcK4AOAJACEAAAAAA==.Detonate:BAAANQAECggICAAAAA==.',
Di='Digem:BAAANQABCgQIBAABNQADCgcIEwASAAAAAA==.Dixinu:BAAANQAECggIDAAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhn+FwDoAAADAAMKPhn+FwDoAAAdAAIKYwrbDgBYAAA1AAQKfyYAAwMACQpgI3kdAE0DAAMACQpgI3kdAE0DAB0ABAo7GXpAAPcAAAAA.Dotsonyourpp:BAAANQADCgQIBAABNQAECgoKHAAQAAkWAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJIwAUAMcgAA==.Dragonwarior:BAABNQAECn8eAAIOAAoKMA9xowDEAQAOAAoKMA9xowDEAQAAAA==.Drykkr:BAABNQAECn8UAAIeAAYKuht7FQCMAQAeAAYKuht7FQCMAQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECgkJFwACAG0MAA==.Element:BAAANQADCgUIBQAAAA==.Ellipsis:BAAANQAECgEIAQAAAA==.Ellyra:BAAANQAECggICgAAAA==.Elpollo:BAABNQAECn8cAAIQAAoKCRbATwAhAgAQAAoKCRbATwAhAgAAAA==.Elsinn:BAAANQADCgQIBAAAAA==.Elthosen:BAAANQAECgUIBQAAAA==.Elvar:BAAANQAECgEIAQAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgoKKQADAEESAA==.',
Ep='Epitome:BAABNQAECn82AAMPAAoK8x1uBgBhAgAPAAoK8x1uBgBhAgAQAAIKegJqyQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.Erolatha:BAAANQAECgEIAQAAAA==.',
Et='Ethereal:BAAANQADCgMIBAAAAA==.Etude:BAAANQAECgQIBwABNQAFFAYIDQACAPEOAA==.',
Eu='Eunha:BAABNQAECn8ZAAIUAAkKTBscDQBXAgAUAAkKTBscDQBXAgABNQAECgkJHQABAIAhAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgkJUwAFAOAPAA==.Evergrey:BAABNQAECn8ZAAIfAAcK4Av9LwAKAQAfAAcK4Av9LwAKAQAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQAECgQIBwAAAA==.Falasdaer:BAAANQAECggIDwAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fastor:BAAANQAECgQIBQAAAA==.Fatalis:BAAANQADCggIHgAAAA==.Fatterblunt:BAACNQAFFH8WAAIEAAcKRgxxCwBZAQAEAAcKRgxxCwBZAQA1AAQKfzsAAgQACgrgHLUUAHQCAAQACgrgHLUUAHQCAAAA.',
Fe='Feldar:BAABNQAECn8tAAIDAAoK3BzXXQB/AgADAAoK3BzXXQB/AgAAAA==.Felmoore:BAAANQAECgQIBAAAAA==.Feronite:BAACNQAFFH8KAAIRAAQK8RJZBADTAAARAAQK8RJZBADTAAA1AAQKfz8AAhEACgoYIOcGABQDABEACgoYIOcGABQDAAAA.',
Fi='Fizzleclaw:BAABNQAECn8nAAMXAAoKyBp3GADGAQAEAAkKvRJ+JQDQAQAXAAgKOh53GADGAQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgoKJwAXAMgaAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlelord:BAAANQAECgMIBQAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fl='Fluchtweg:BAABNQAECn8bAAMgAAkKyhfXBwDkAQAgAAkKyhfXBwDkAQALAAMKUhO65gCEAAABNQAECgoKLAAbAHIgAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAABNQAECn8aAAICAAkKZxN5awByAQACAAkKZxN5awByAQAAAA==.',
Fr='Fredwin:BAABNQAECn8UAAILAAgKYQuusABvAQALAAgKYQuusABvAQAAAA==.Free:BAAANQAECgMIAwABNQAECgQIBAASAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBAASAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Galicos:BAAANQAECggIDQAAAA==.Ganthex:BAAANQADCgUIBQAAAA==.Gapper:BAABNQAECn9YAAIWAAoKtiEyCQBAAwAWAAoKtiEyCQBAAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAhALwgAA==.Gargodath:BAAANQABCggIEQAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECn8+AAIiAAoKSyEpEgAGAwAiAAoKSyEpEgAGAwAAAA==.Glitterpants:BAAANQAECgcIBQAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8gAAIOAAkKlxURfgAgAgAOAAkKlxURfgAgAgAAAA==.',
Go='Gojira:BAABNQAECn8dAAIMAAYKVx4JSADzAQAMAAYKVx4JSADzAQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECn8jAAMUAAkK/BgDEwBNAgAUAAkK/BgDEwBNAgAVAAEKCA+KbAAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIDwASAAAAAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAABNQAECn8tAAIOAAoK/hNXUQAKAgAOAAoK/hNXUQAKAgAAAA==.',
Ha='Haerin:BAAANQAECgYIDAABNQAECgkJHQABAIAhAA==.Hakoa:BAAANQAECgUIBQAAAA==.Harnel:BAABNQAECn8jAAIDAAYKNgQnHwHrAAADAAYKNgQnHwHrAAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgYICwAAAA==.Hellborne:BAAANQABCgIIAgABNQAECgQICAASAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holygeeked:BAAANQAECgUIBQAAAA==.Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQASAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQAECgcIDAAAAA==.',
Hy='Hyrn:BAAANQADCgMIAwAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAFFAQICgARAPESAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgUIBgAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAABNQAECn8aAAIQAAoKrB3zNAAgAwAQAAoKrB3zNAAgAwAAAA==.Kaliel:BAAANQADCggIGgAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgYIBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwALAEsRAA==.',
Ke='Kernelpanic:BAACNQAFFH8WAAQGAAYK7R6pAwBMAQAGAAUKRh6pAwBMAQAHAAIKZBmZFACZAAAFAAIKAAAlNgAnAAA1AAQKfy8AAwYACgopImUUAE4CAAYACQpaIWUUAE4CAAcABArpF36JAJMAAAAA.Keyoshi:BAAANQAECggIDgAAAA==.',
Ki='Kickrocks:BAAANQAECggIAgAAAA==.Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYIDgAAAA==.Kirkle:BAABNQAECn9VAAIaAAoK7xyHAQCoAgAaAAoK7xyHAQCoAgAAAA==.',
Ko='Kovie:BAAANQAECgIIAgAAAA==.Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYIDAAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwALAEsRAA==.',
Ku='Kulrath:BAAANQAECggIDQAAAA==.',
Kw='Kwovie:BAABNQAECn8eAAIXAAkK4BneEABTAgAXAAkK4BneEABTAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8oAAIDAAgKgRFCqgDLAQADAAgKgRFCqgDLAQAAAA==.Landrick:BAAANQAECggICwAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgYICgABNQAECgcIFAAZAHcPAA==.Lavasaurus:BAABNQAECn8UAAIZAAcKdw/OFQDaAAAZAAcKdw/OFQDaAAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAABNQAECn8aAAMiAAoKXQuv4AA/AQAiAAkKtwyv4AA/AQAWAAMKBwKBbAB8AAAAAA==.',
Li='Lifebloomz:BAABNQAECn8sAAMTAAgKmRUKKQCoAQATAAgKmRUKKQCoAQAXAAUKEQOkVABuAAAAAA==.Lilfluffcc:BAABNQAECn8gAAIRAAoKJxF1EQBSAgARAAoKJxF1EQBSAgAAAA==.',
Lo='Lockward:BAABNQAECn8uAAMLAAoKKxr1QgANAgALAAoKmxj1QgANAgAaAAEK9BYWLgBLAAAAAA==.Lorblor:BAABNQAECn8kAAIIAAoK4Rv1HQAdAgAIAAoK4Rv1HQAdAgAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8qAAINAAkK5RZuVgAgAgANAAkK5RZuVgAgAgAAAA==.Lunafox:BAABNQAECn8sAAMCAAoKWBl0IwCnAgACAAoKWBl0IwCnAgANAAcK+AkygAAQAQAAAA==.Lunamae:BAABNQAECn8fAAIQAAkKDA7SzgDoAQAQAAkKDA7SzgDoAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgoKVwABAJoeAA==.Luvvyyaa:BAABNQAECn9XAAQBAAoKmh4NKwCdAgABAAoKmh4NKwCdAgAjAAIKwQp8IABeAAAfAAEKdwniYgA2AAAAAA==.Luvyya:BAAANQAECggICwABNQAECgoKVwABAJoeAA==.',
Ly='Lythomancer:BAABNQAECn8fAAIaAAkK4QcAIQBpAQAaAAkK4QcAIQBpAQAAAA==.Lythoras:BAAANQAECgMIBAABNQAECgkJHwAaAOEHAA==.',
Ma='Maddeena:BAAANQAECgYIEwAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAILAAUKSxGYEQBzAQALAAUKSxGYEQBzAQA1AAQKfzEAAgsACQpUIq8ZACADAAsACQpUIq8ZACADAAAA.',
Mc='Mcmercie:BAABNQAECn83AAMdAAoKWhDCHACKAQAdAAoKWhDCHACKAQADAAEKAAAl3gEAAAAAAA==.',
Me='Mechacooter:BAACNQAFFH8GAAIkAAMKlAhGDQB+AAAkAAMKlAhGDQB+AAA1AAQKfysAAiQACgrBGuMbAJ8CACQACgrBGuMbAJ8CAAAA.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8pAAIQAAgKHBKbkACFAQAQAAgKHBKbkACFAQAAAA==.Melchiorr:BAACNQAFFH8IAAIgAAIK2RAUBwCYAAAgAAIK2RAUBwCYAAA1AAQKfz8AAiAACgqoG5ICAPQCACAACgqoG5ICAPQCAAAA.Melynne:BAABNQAECn8uAAICAAoKExUFOgAvAgACAAoKExUFOgAvAgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECggIEQASAAAAAA==.Minji:BAABNQAECn8YAAIgAAgKYRpNCQDvAQAgAAgKYRpNCQDvAQABNQAECgkJHQABAIAhAA==.Minsoo:BAACNQAFFH8IAAIUAAIK8hgbCQCWAAAUAAIK8hgbCQCWAAA1AAQKfzoAAhQACgpSIWkDAJwDABQACgpSIWkDAJwDAAAA.',
Ml='Mlrgl:BAABNQAECn8qAAMiAAoKUCOLQwCgAgAiAAoKUCOLQwCgAgAWAAUK0xJ3RgAnAQAAAA==.Mlrglet:BAAANQAECggICgABNQAECgoKKgAiAFAjAA==.Mlrglo:BAAANQAECgUJBgABNQAECgoKKgAiAFAjAA==.',
Mo='Mormegil:BAABNQAECn8eAAQHAAoKrhaXLwDuAQAHAAoKPxOXLwDuAQAFAAUKbhnYagBIAQAGAAMKIx2kjADyAAAAAA==.Moshimoshi:BAACNQAFFH8NAAMCAAYK8Q5UEgA7AQACAAUKjgtUEgA7AQANAAEKAADxMgAAAAA1AAQKfx0AAwIACgpcFcxKADgCAAIACgpcFcxKADgCAA0AAwo6FRPEAIMAAAAA.Motosake:BAAANQADCgUIBQABNQAFFAYIDQACAPEOAA==.',
Mt='Mtx:BAABNQAECn8VAAINAAoK1hE6OQDvAQANAAoK1hE6OQDvAQAAAA==.',
Mu='Muriana:BAAANQADCgYIBwAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAABNQAECn8kAAQYAAkK5hU0EADdAAAYAAUKkA00EADdAAAlAAcK1Q4nJQDYAAAZAAUKmRFSGAC2AAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAABNQAECn8UAAIIAAkK7gl+PQBHAQAIAAkK7gl+PQBHAQABNQAFFAMIBgAkAJQIAA==.',
Ne='Nessará:BAABNQAECn9KAAIBAAoKgRUkNQBqAgABAAoKgRUkNQBqAgAAAA==.Newgate:BAAANQAECgYIDgAAAA==.',
Ni='Nightgodjuju:BAABNQAECn8tAAMPAAoKjBHYCwDgAQAPAAoKjBHYCwDgAQAQAAEKXwJhaAEmAAAAAA==.Nikna:BAAANQAECgUICwABNQAFFAcIFAAiAEMcAA==.',
Nu='Nudacris:BAAANQAECggIDwABNQAECgoKKgAiAFAjAA==.Nuocbeo:BAAANQAECgEIAQAAAA==.Nuraga:BAABNQAECn8rAAMhAAkK9CJcBQAhAwAhAAkK9CJcBQAhAwAOAAEKcgn0KQE2AAAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAABNQAECn8ZAAIWAAgK6BaBNQCiAQAWAAgK6BaBNQCiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgcIDQAAAA==.Pandakyle:BAABNQAECn8jAAIUAAkKxyC3BgArAwAUAAkKxyC3BgArAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECggIEAASAAAAAA==.Pattilicious:BAABNQAECn8VAAIDAAkKKQ3NvgCfAQADAAkKKQ3NvgCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8jAAMZAAoKZBdDFwDXAQAZAAcKhxdDFwDXAQAlAAgKXhZ/HQAqAQAAAA==.',
Pi='Pierres:BAAANQADCgMIAwAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn8/AAMdAAoK0hhyEAAjAgAdAAoK0hhyEAAjAgADAAIK5gs9cAFuAAAAAA==.',
Pr='Protsucks:BAAANQAECgYIBgAAAA==.',
Py='Pyrug:BAAANQADCgYICwABNQAECgoKNwAaAK0aAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgoKOAAiAFwSAA==.',
Qu='Quilue:BAAANQAECggIDAAAAA==.',
Ra='Rankak:BAAANQAECgIIAgABNQAFFAIICAAUAPIYAA==.Rannmagnison:BAABNQAECn8vAAIDAAgKuwYx6QBJAQADAAgKuwYx6QBJAQAAAA==.Raquoon:BAABNQAECn8cAAIhAAYKcQohLAChAAAhAAYKcQohLAChAAAAAA==.Rasonia:BAAANQAECgcIBwABNQAFFAIIBQABAIMKAA==.Razzalghoul:BAABNQAECn8eAAMHAAgKDhIOPwDOAQAHAAgKDhIOPwDOAQAGAAQKEQd2qgChAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECgkJFQAbAKIMAA==.Reuli:BAAANQAECgMIBgAAAA==.Reze:BAACNQAFFH8IAAIVAAYKbiQLBAC0AQAVAAYKbiQLBAC0AQA1AAQKfzgAAhUACgquJdkCAFADABUACgquJdkCAFADAAE1AAUUCgpAAAgAJiYA.',
Rh='Rhaeynera:BAABNQAECn8nAAIZAAcK0QRZFwDCAAAZAAcK0QRZFwDCAAAAAA==.Rhialle:BAAANQADCgQIBgABNQAECgEIAQASAAAAAA==.Rhinne:BAAANQAECgYICwAAAA==.',
Ri='Riezen:BAABNQAECn8sAAIGAAkKVBT5KQCVAQAGAAkKVBT5KQCVAQAAAA==.Rinorik:BAABNQAECn8pAAMLAAgKmB4JbwASAgALAAcKYh4JbwASAgAaAAIK3B+/QwC2AAAAAA==.',
Ro='Rockbiter:BAAANQAECgIIAgAAAA==.Rockhhard:BAAANQAECgMIAgAAAA==.Roeken:BAABNQAECn9BAAIOAAoKTxSnTQAWAgAOAAoKTxSnTQAWAgAAAA==.Rollingman:BAAANQAECgYICgAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8rAAIFAAoKoyObFQAAAwAFAAoKoyObFQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECn8vAAIWAAoKjiD6CwB7AgAWAAoKjiD6CwB7AgAAAA==.',
Sa='Samsó:BAABNQAECn8zAAMMAAoKjRaBPAAlAgAMAAoKjRaBPAAlAgADAAEKAACoowE1AAAAAA==.Sapharina:BAACNQAFFH8FAAMBAAIKgwpYMABkAAABAAIKgwpYMABkAAAfAAIKsgClFwA8AAA1AAQKf0AAAwEACgrnF8VTACgCAAEACgrnF8VTACgCAB8ACQrkCHAeAJsBAAAA.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8sAAQbAAoKciC1CADHAgAbAAoKciC1CADHAgATAAcK8Bd5LAC4AQAXAAIKUg22UABgAAAAAA==.Schreckstoff:BAABNQAECn8qAAINAAkKrBQLXQALAgANAAkKrBQLXQALAgAAAA==.',
Se='Searfang:BAACNQAFFH8KAAINAAMKVxHiEQDeAAANAAMKVxHiEQDeAAA1AAQKfy0AAg0ACgozGts+AHoCAA0ACgozGts+AHoCAAAA.Sematic:BAABNQAECn8dAAMgAAoK/iAjAwCPAgAgAAgKeCEjAwCPAgALAAYKJxlmmAAoAQABNQAFFAcIGwAOAL0dAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shadrielis:BAAANQAECgQIBAABNQAECgoKKgAiAFAjAA==.Shamor:BAAANQAECgYIDgAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA2HVQCCAQAEAAcKvA2HVQCCAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAABNQAECn85AAIbAAoK0hetDQDyAQAbAAoK0hetDQDyAQAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skytec:BAAANQAECgIIAwAAAA==.Skëëts:BAAANQAECgIIAgAAAA==.',
Sl='Slampoof:BAAANQABCggIEAAAAA==.Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAASAAAAAA==.Smashmaster:BAABNQAECn8cAAMOAAgKQw25hwB1AQAOAAgKKAy5hwB1AQAcAAMKJA9CLABYAAAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwASAAAAAA==.',
Sn='Snowscayia:BAABNQAECn+KAAMTAAoKLiRgAwDNAwATAAoKLiRgAwDNAwAEAAgK4xVHNgA5AgAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBziIQC/AgAEAAkKbBziIQC/AgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8pAAIPAAgKYBtKCwAOAgAPAAgKYBtKCwAOAgAAAA==.',
Sq='Squadie:BAABNQAECn80AAIiAAoK4QqJgQC2AQAiAAoK4QqJgQC2AQAAAA==.Squanchs:BAACNQAFFH8MAAICAAQKXiRaDQCKAQACAAQKXiRaDQCKAQA1AAQKfysAAgIACgrcJeADAKwDAAIACgrcJeADAKwDAAE1AAQKBggHABIAAAAA.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgcICQAAAA==.',
St='Stoot:BAAANQAECgMIBAABNQAECgUIFAAVABwkAA==.Stormdaka:BAAANQAECgEIAQABNQAECgoKLAAMAC8hAA==.Story:BAAANQADCgUIEAAAAA==.Sturm:BAAANQADCgEIAQAAAA==.Styrcius:BAABNQAECn8xAAIdAAkKrRz1EAAcAgAdAAkKrRz1EAAcAgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECggIEAAAAA==.Suniah:BAABNQAECn8WAAMhAAkKHQkZJQDRAAAOAAYKvgZ95wAWAQAhAAkKqwgZJQDRAAAAAA==.Sustmage:BAAANQAECgEIAQABNQAFFAcIGwAOAL0dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQAECgIIAQAAAA==.Süß:BAAANQADCgIIAgABNQAECgoKLAAbAHIgAA==.',
Ta='Tabius:BAABNQAECn8UAAIbAAYKKBnXEwC/AQAbAAYKKBnXEwC/AQAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.Taln:BAAANQABCgEIAQABNQAECgoKHgAHAK4WAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDQASAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAABNQAECn8ZAAIDAAgKSwtc3AAjAQADAAgKSwtc3AAjAQAAAA==.',
Th='Thelorìn:BAABNQAECn8lAAIXAAkK8BsoDQCUAgAXAAkK8BsoDQCUAgAAAA==.Thiccdiq:BAABNQAECn8uAAMeAAkKQh3ZBQA3AgAeAAgKXx7ZBQA3AgAVAAQKFA4JOADjAAAAAA==.Thiccgirl:BAAANQABCgMIBAAAAA==.Thirstycow:BAABNQAECn8aAAMCAAkKNQWvoAA1AQACAAkKNQWvoAA1AQANAAcKoAIpxwAEAQAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thornmar:BAAANQAECgQIEQAAAA==.Thosen:BAABNQAECn8gAAMEAAoKrgxbMACEAQAEAAoKWApbMACEAQAXAAQK0BN/TwCBAAAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECn9SAAIiAAoKCiYKCACdAwAiAAoKCiYKCACdAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAACNQAFFH8RAAIEAAUKBBLVEgDfAAAEAAUKBBLVEgDfAAA1AAQKfzAAAgQACgptHVAeANgCAAQACgptHVAeANgCAAAA.Tråitors:BAABNQAECn8kAAILAAgKZhP4oQCSAQALAAgKZhP4oQCSAQAAAA==.',
Ts='Tsarevich:BAABNQAECn8kAAIQAAcKvwYp4QDrAAAQAAcKvwYp4QDrAAAAAA==.',
Tw='Twileaf:BAABNQAECn8bAAITAAYKAgnTRgD7AAATAAYKAgnTRgD7AAAAAA==.',
['Té']='Térror:BAAANQADCgIIAgAAAA==.',
Ul='Ully:BAABNQAECn8UAAIRAAgKbRT0GADXAQARAAgKbRT0GADXAQAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIGAAgKIhMCWQCsAQAGAAgKIhMCWQCsAQAAAA==.Unug:BAAANQADCggIDgABNQAECgoKNwAaAK0aAA==.',
Ut='Uthmansur:BAABNQAECn8kAAIcAAkKLgZ6GQDwAAAcAAkKLgZ6GQDwAAAAAA==.',
Va='Varkbyte:BAABNQAECn8iAAMBAAYKiRLqiQA7AQABAAYKiRLqiQA7AQAfAAEKAABVfwAAAAAAAA==.Varrik:BAABNQAECn8tAAMOAAgKsR8YUACZAgAOAAgKsR8YUACZAgAcAAEK0R3NMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8sAAMBAAoK8hmwLQCPAgABAAoK8hmwLQCPAgAjAAcKRA+jCAAsAQAAAA==.Volklin:BAABNQAECn8eAAICAAcKigO9pQDRAAACAAcKigO9pQDRAAAAAA==.Volyria:BAAANQADCgEIAQAAAA==.Voyageurs:BAACNQAFFH8FAAIbAAIK6w4vAwCFAAAbAAIK6w4vAwCFAAA1AAQKfykAAhsACgqQHUQHAO4CABsACgqQHUQHAO4CAAAA.',
Vy='Vynn:BAAANQADCgQIBAABNQAECgkJFwACAG0MAA==.Vyrka:BAABNQAECn8nAAIiAAcKCwuvwQAuAQAiAAcKCwuvwQAuAQAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBgABNQAECgoKQAAPAMgbAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcIDwAAAA==.Werebear:BAAANQAECgYICgABNQAECgcIDAASAAAAAA==.Werewithal:BAAANQADCgUIBQABNQAECgkJKgANAKwUAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgYICAAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECggIJAALAGYTAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQASAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Wiindsslashh:BAAANQAECgYIBwAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Windsslashh:BAAANQAECgEIAgAAAA==.Wish:BAABNQAECn82AAMZAAoKPhoIBQB5AgAZAAoKPhoIBQB5AgAYAAYKahN5DwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECgkJHQABAIAhAA==.Wonyoung:BAABNQAECn8dAAMBAAkKgCFPKADIAgABAAkKgCFPKADIAgAfAAEKsRISXgA+AAAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.Wråth:BAAANQAECgYIBgAAAA==.',
Wu='Wuthrad:BAAANQAECgcIEQAAAA==.',
Wy='Wyze:BAAANQAECgEIAQAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.',
Xe='Xelienn:BAABNQAECn8rAAMHAAoKex6IIgB6AgAHAAoKex6IIgB6AgAGAAIKMAPW0wBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAABNQAECn83AAIBAAoKMRx/JADCAgABAAoKMRx/JADCAgAAAA==.Xilhaunt:BAABNQAECn9XAAQaAAoK2R2YAgBHAgAaAAoKpRuYAgBHAgALAAoKZBrnNQA5AgAgAAQKShSnFQDwAAAAAA==.',
Xo='Xoilcast:BAAANQAECgMIAwAAAA==.Xoilkick:BAAANQAECgYIEAAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAABNQAECn8bAAMKAAgKcRE3EwAYAQAKAAcKvxM3EwAYAQAIAAYKCgg6UgDaAAAAAA==.Xorm:BAAANQAECggIEgAAAA==.',
['Xê']='Xêna:BAABNQAECn8XAAIiAAkKWQfuoQBvAQAiAAkKWQfuoQBvAQAAAA==.',
['Xì']='Xì:BAAANQAECgEIAQAAAA==.',
Ya='Yaktac:BAAANQADCgIIAgAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgoKWAAWALYhAA==.',
Ye='Yellowsnøw:BAAANQAECgUIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgcIDQABNQAFFAYIDQACAPEOAA==.',
Za='Zaak:BAABNQAECn9LAAMmAAoKrCVTAAB1AwAmAAoKrCVTAAB1AwAiAAEK3yLwKAFkAAAAAA==.Zamari:BAABNQAECn8lAAINAAkK6wITmgDUAAANAAkK6wITmgDUAAAAAA==.Zanzabar:BAABNQAECn8XAAIbAAkKWA2pHAAmAQAbAAkKWA2pHAAmAQAAAA==.',
Ze='Zelfie:BAAANQAECgIIAQAAAA==.Zeliek:BAABNQAECn9JAAIMAAoKKCHXDgBLAwAMAAoKKCHXDgBLAwAAAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.Zeus:BAAANQADCgEIAQAAAA==.',
Zo='Zoerina:BAABNQAECn8dAAILAAoKqg/KUwDYAQALAAoKqg/KUwDYAQAAAA==.Zoobilong:BAABNQAECn8pAAIDAAoKQRJ9ggAjAgADAAoKQRJ9ggAjAgAAAA==.',
Zx='Zxak:BAAANQAECgQIBAABNQAECgoKSwAmAKwlAA==.',
['Zë']='Zën:BAABNQAECn9EAAMQAAoKJA4mawDcAQAQAAoKJA4mawDcAQAPAAEKCQ8xTQAsAAAAAA==.',
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
