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

local lookup = {'Priest-Holy','Shaman-Restoration','Paladin-Retribution','Druid-Balance','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Paladin-Holy','Shaman-Elemental','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Druid-Guardian','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Druid-Feral','Warrior-Fury','Paladin-Protection','Monk-Brewmaster','Warrior-Protection','Hunter-BeastMastery','Priest-Discipline','Priest-Shadow','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQAECgEIAQAAAA==.',
Ae='Aeliar:BAAANQAECgIIAgAAAA==.Aenimal:BAAANQAECgQICAAAAA==.',
Ah='Ahavati:BAAANQAECgEIAQAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECgoKQAABAOcXAA==.Akittymeow:BAAANQAECgIIAwAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Aleshock:BAAANQABCgQICAAAAA==.',
Am='Amberlie:BAAANQAECggIEgAAAA==.Aminni:BAABNQAECn8gAAICAAgKVxHcZQDbAQACAAgKVxHcZQDbAQAAAA==.Amorgal:BAAANQAECggICAAAAA==.Amorir:BAABNQAECn83AAIDAAoKNReNUgAjAgADAAoKNReNUgAjAgAAAA==.Amorydalias:BAAANQAECgMIBQAAAA==.',
An='Anastala:BAABNQAECn8hAAIEAAkKsQ8sSQDEAQAEAAkKsQ8sSQDEAQAAAA==.Andeddo:BAACNQAFFH8JAAMFAAMKYw17GACZAAAFAAMKCQp7GACZAAAGAAEKWRZ3HgBTAAA1AAQKfzkABAYACgqaHdsZAPICAAYACQo7HdsZAPICAAcACAocFIk/AMsBAAUABAr5GORIAAwBAAAA.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJBAAAAA==.',
Ar='Archontas:BAABNQAECn8kAAIEAAoKPB22GwDrAgAEAAoKPB22GwDrAgAAAA==.Aregon:BAAANQADCgQIBAAAAA==.Ariodecay:BAAANQAECgUIBwAAAA==.Ariodh:BAACNQAFFH8bAAMIAAcKmCObBAAgAgAIAAYKyiWbBAAgAgAJAAYKHBgqBAA8AQA1AAQKf0kABAgACgqkJpgCAMwDAAgACgpiJpgCAMwDAAkACQoMJY4GAO0CAAoABgqeJi0GADECAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBQAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFH8PAAILAAUKABOfGwAaAQALAAUKABOfGwAaAQA1AAQKfzYAAgsACgovHuVBAIwCAAsACgovHuVBAIwCAAAA.',
At='Athenà:BAAANQABCgYICQAAAA==.Atonedaka:BAAANQAECgIIAwABNQAECgoKLAAMAC8hAA==.',
Av='Avye:BAABNQAECn8vAAMNAAkKlBjvPwC+AQANAAkKlBjvPwC+AQACAAEKSgbtLQEhAAAAAA==.',
['Aè']='Aèriah:BAAANQAECgEIAQAAAA==.',
Ba='Bananus:BAAANQAECgcIDwAAAA==.Banthr:BAABNQAECn8bAAIOAAoK5g3NpADBAQAOAAoK5g3NpADBAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Beeps:BAAANQAECgUIBQAAAA==.Benchedwin:BAAANQAECgcIBgAAAA==.',
Bi='Bigcow:BAABNQAECn8UAAINAAcKnhHNgQCgAQANAAcKnhHNgQCgAQAAAA==.Bigdeeps:BAABNQAECn8oAAIOAAoKASP0GwBIAwAOAAoKASP0GwBIAwAAAA==.',
Bl='Blackolives:BAABNQAECn86AAIBAAkKNSO/DABrAwABAAkKNSO/DABrAwAAAA==.Blastcannon:BAABNQAECn8gAAMPAAgKowMTHgD8AAAPAAcK1wMTHgD8AAAQAAQK5QGhrwFiAAAAAA==.Bluejuly:BAAANQABCgYICQAAAA==.Blutønium:BAAANQAECgEIAQAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQAECgEIAQABNQAFFAQICgARAPESAA==.',
Br='Bravehearth:BAABNQAECn8XAAIDAAoK8A4rcwDVAQADAAoK8A4rcwDVAQABNQAECgUIBQASAAAAAA==.',
Bu='Bubbadoo:BAABNQAECn8rAAMEAAkKrxLHLACFAQAEAAkKrxLHLACFAQATAAEKmgDTgwAMAAAAAA==.Bulan:BAABNQAECn84AAIUAAkK9iMkBABpAwAUAAkK9iMkBABpAwAAAA==.',
Ca='Candypants:BAABNQAECn8yAAMUAAoKFBjRFQAeAgAUAAoKFBjRFQAeAgAVAAEKMgdMWgAxAAAAAA==.Caoth:BAAANQAECgQIBwAAAA==.Cappilon:BAABNQAECn8zAAIPAAoKPiF9AwANAwAPAAoKPiF9AwANAwAAAA==.Carcus:BAAANQAECgcIEQAAAA==.Cayleedah:BAABNQAECn8VAAIWAAYK7AL9QACMAAAWAAYK7AL9QACMAAAAAA==.Cayssaris:BAABNQAECn8ZAAIXAAYKvh7dIgBVAQAXAAYKvh7dIgBVAQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECn84AAMYAAoKLhx+BAC/AgAYAAoK2Rt+BAC/AgAZAAYKNRsxGQC2AQAAAA==.',
Ch='Chaewon:BAAANQAECgMIAwABNQAECgkJHQABAIAhAA==.Chaoticoreo:BAAANQAECgEIAgAAAA==.Chappedlips:BAAANQAECggIEQAAAA==.Cheetor:BAAANQAECggICQABNQAECgoKVAAWALYhAA==.Chidaka:BAAANQAECgEIBQABNQAECgoKLAAMAC8hAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAACNQAFFH8JAAILAAUKLBKtFwDaAAALAAUKLBKtFwDaAAA1AAQKfywAAwsACgqxGKU2ACUCAAsACgqxGKU2ACUCABoABQqBDas3AOIAAAAA.Cosairi:BAABNQAECn8jAAICAAoKcRPjYQB6AQACAAoKcRPjYQB6AQAAAA==.Cougztroll:BAABNQAECn8uAAMXAAoKoxPPGgCYAQAXAAoK6hLPGgCYAQAbAAEKeBQGRQAzAAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAABNQAECn8hAAIRAAkKHyOVCACNAgARAAkKHyOVCACNAgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgoKOAAYAC4cAA==.',
Cu='Cuttercupx:BAAANQAECgUICwABNQAECgcIDwASAAAAAA==.',
Da='Dahn:BAAANQAECggIEAABNQAECgoKVAAWALYhAA==.Dakadin:BAABNQAECn8sAAIMAAoKLyGvJADYAgAMAAoKLyGvJADYAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECn89AAIDAAoKJhoRVACZAgADAAoKJhoRVACZAgAAAA==.Darkenedstar:BAAANQAECgIIAwABNQAECgQICAASAAAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECn9TAAMFAAkK4A+NPQA8AQAFAAgK3xGNPQA8AQAHAAQKdwTtjAB1AAAAAA==.Dashy:BAAANQAECgUIBQAAAA==.Dawnstone:BAAANQAECgQIDQAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAABNQAECn83AAMaAAoKrRr4AgAQAgAaAAgKvRj4AgAQAgALAAoKvRb9PgAIAgAAAA==.Deafsmash:BAAANQAECgIIBwABNQAECgkJMgAGACYeAA==.Delamyr:BAAANQABCgIIAwABNQADCgYIBgASAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Delusional:BAAANQAECgEIAQAAAA==.Denaric:BAAANQAECgUICAABNQAECgkJIgAYAOYVAA==.Destroyevsky:BAABNQAECn8dAAIcAAcKigMUIgB/AAAcAAcKigMUIgB/AAAAAA==.Detonate:BAAANQAECggICQAAAA==.',
Di='Digem:BAAANQAECgEIAQABNQAECgEIBgASAAAAAA==.Dixinu:BAAANQAECggIDAAAAA==.',
Do='Dolphinz:BAACNQAFFH8GAAMDAAQKPhn+FwDoAAADAAMKPhn+FwDoAAAdAAIKYwrbDgBYAAA1AAQKfyYAAwMACQpgI3kdAE0DAAMACQpgI3kdAE0DAB0ABAo7GXpAAPcAAAAA.Dotsonyourpp:BAAANQADCgQIBAABNQAECgoKHAAQAAkWAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJIwAUAMcgAA==.Dragonwarior:BAABNQAECn8eAAIOAAoKMA9xowDEAQAOAAoKMA9xowDEAQAAAA==.Drykkr:BAABNQAECn8UAAIeAAYKuht7FQCMAQAeAAYKuht7FQCMAQAAAA==.',
Eh='Ehlana:BAAANQAECgEIAQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggIEgASAAAAAA==.Element:BAAANQAECgEIAQAAAA==.Ellipsis:BAAANQAECgEIAQAAAA==.Ellyra:BAAANQAECgYIBgAAAA==.Elpollo:BAABNQAECn8cAAIQAAoKCRaoSQAjAgAQAAoKCRaoSQAjAgAAAA==.Elthosen:BAAANQAECgUIBAAAAA==.Elvar:BAAANQAECgEIAgAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECgoKKQADAEESAA==.',
Ep='Epitome:BAABNQAECn80AAMPAAoK8x2cBQBnAgAPAAoK8x2cBQBnAgAQAAIKegJqyQEzAAAAAA==.',
Er='Erid:BAAANQAECgcIEwAAAA==.Erolatha:BAAANQAECgEIAQAAAA==.',
Et='Ethereal:BAAANQADCgMIAwAAAA==.Etude:BAAANQAECgQIBwABNQAFFAYIDQACAPEOAA==.',
Eu='Eunha:BAABNQAECn8YAAIUAAkKTBsnDABaAgAUAAkKTBsnDABaAgABNQAECgkJHQABAIAhAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgkJUwAFAOAPAA==.Evergrey:BAAANQAECgQIEAAAAA==.Evermoons:BAABNQAECn8UAAITAAYK8hicLgCmAQATAAYK8hicLgCmAQAAAA==.',
Fa='Falaria:BAAANQAECgUIBQAAAA==.Falasdaer:BAAANQAECgcIDwAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fastor:BAAANQAECgQIBQAAAA==.Fatalis:BAAANQAECgEIAQAAAA==.Fatterblunt:BAACNQAFFH8WAAIEAAcKRgyJCQBbAQAEAAcKRgyJCQBbAQA1AAQKfzsAAgQACgrgHEITAHYCAAQACgrgHEITAHYCAAAA.',
Fe='Feldar:BAABNQAECn8tAAIDAAoK3BzXXQB/AgADAAoK3BzXXQB/AgAAAA==.Felmoore:BAAANQAECgQIBAAAAA==.Feronite:BAACNQAFFH8KAAIRAAQK8RLpAwDWAAARAAQK8RLpAwDWAAA1AAQKfz8AAhEACgoYIOcGABQDABEACgoYIOcGABQDAAAA.',
Fi='Fizzleclaw:BAABNQAECn8mAAMXAAoKIhpnFwC6AQAEAAkKvRLPIgDRAQAXAAgKXR1nFwC6AQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgoKJgAXACIaAA==.Fizzlelock:BAAANQADCgYIBwAAAA==.Fizzlelord:BAAANQAECgIIAgAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fl='Fluchtweg:BAAANQAECggIEgABNQAECgoKLAAbAHIgAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAABNQAECn8YAAICAAkKZxNnYwB1AQACAAkKZxNnYwB1AQAAAA==.',
Fr='Fredwin:BAABNQAECn8UAAILAAgKYQuusABvAQALAAgKYQuusABvAQAAAA==.Free:BAAANQAECgMIAwABNQAECgQIBQASAAAAAA==.Frenn:BAAANQAECgEIAQAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBQASAAAAAA==.Furvert:BAAANQAECgcIDwAAAA==.',
Ga='Galicos:BAAANQAECgYIDAAAAA==.Ganthex:BAAANQADCgUIBQAAAA==.Gapper:BAABNQAECn9UAAIWAAoKtiEyCQBAAwAWAAoKtiEyCQBAAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAUIEQAfALwgAA==.Gargodath:BAAANQABCggIEQAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECn84AAIgAAoKfSB7FQDpAgAgAAoKfSB7FQDpAgAAAA==.Glitterpants:BAAANQAECgcIBgAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECn8gAAIOAAkKlxURfgAgAgAOAAkKlxURfgAgAgAAAA==.',
Go='Gojira:BAABNQAECn8dAAIMAAYKVx6hQAD/AQAMAAYKVx6hQAD/AQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECn8jAAMUAAkK/BgDEwBNAgAUAAkK/BgDEwBNAgAVAAEKCA+KbAAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIEwASAAAAAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAABNQAECn8oAAIOAAoKMRJFUQD4AQAOAAoKMRJFUQD4AQAAAA==.',
Ha='Haerin:BAAANQAECgYIDAABNQAECgkJHQABAIAhAA==.Hairydresden:BAAANQAECgEIBAAAAA==.Hakoa:BAAANQAECgUIBQAAAA==.Harnel:BAABNQAECn8jAAIDAAYKNgQnHwHrAAADAAYKNgQnHwHrAAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgYIDAAAAA==.Hellborne:BAAANQAECgEIAQABNQAECgQICAASAAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDwASAAAAAA==.Hoyer:BAAANQAECgIIBAAAAA==.',
Hu='Humbledrink:BAAANQAECgUIBQAAAA==.',
Hy='Hyrn:BAAANQADCgMIAwAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBQAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgcICAABNQAFFAQICgARAPESAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgUICAAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Ju='Junio:BAAANQADCggICAAAAA==.',
Jy='Jyade:BAAANQAECgEIBAAAAA==.',
Ka='Kaiserice:BAABNQAECn8aAAIQAAoKrB3zNAAgAwAQAAoKrB3zNAAgAwAAAA==.Kaliel:BAAANQADCggIGgAAAA==.Kamarra:BAAANQAECgEIAwAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgYIBgAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwALAEsRAA==.',
Ke='Kernelpanic:BAACNQAFFH8WAAQGAAYK7R7eAgBZAQAGAAUKRh7eAgBZAQAHAAIKZBmZFACZAAAFAAIKAAAlNgAnAAA1AAQKfy8AAwYACgopIqoSAFMCAAYACQpaIaoSAFMCAAcABArpFwqBAJYAAAAA.Keyoshi:BAAANQAECggIDgAAAA==.',
Ki='Kickrocks:BAAANQAECggIAgAAAA==.Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQAECgEIAgAAAA==.Kirkle:BAABNQAECn9MAAIaAAoK8huzAQCGAgAaAAoK8huzAQCGAgAAAA==.',
Ko='Kovie:BAAANQAECgIIAgAAAA==.Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYIDAAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwALAEsRAA==.',
Ku='Kulrath:BAAANQAECggIDQAAAA==.',
Kw='Kwovie:BAABNQAECn8eAAIXAAkK4BneEABTAgAXAAkK4BneEABTAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAgAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECn8oAAIDAAgKgRFCqgDLAQADAAgKgRFCqgDLAQAAAA==.Landrick:BAAANQAECggICwAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgYICgABNQAECgcIFAAZAHcPAA==.Lavasaurus:BAABNQAECn8UAAIZAAcKdw+NFADaAAAZAAcKdw+NFADaAAAAAA==.',
Le='Leafstorm:BAAANQAECgEIBgAAAA==.Leokenoso:BAAANQAECgMIBwAAAA==.Lesclaypool:BAAANQADCgcIDgAAAA==.Lewd:BAABNQAECn8aAAMgAAoKXQuv4AA/AQAgAAkKtwyv4AA/AQAWAAMKBwKBbAB8AAAAAA==.',
Li='Lifebloomz:BAABNQAECn8sAAMTAAgKmRVwJQCpAQATAAgKmRVwJQCpAQAXAAUKEQODTwBuAAAAAA==.Lilfluffcc:BAABNQAECn8gAAIRAAoKJxF1EQBSAgARAAoKJxF1EQBSAgAAAA==.',
Lo='Lockward:BAABNQAECn8uAAMLAAoKKxoGPQAQAgALAAoKmxgGPQAQAgAaAAEK9BaYLABJAAAAAA==.Lorblor:BAABNQAECn8kAAIIAAoK4RuBGwAfAgAIAAoK4RuBGwAfAgAAAA==.Lowang:BAAANQAECgIIAwAAAA==.Lowmeinn:BAAANQAECgUJCgAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECn8qAAINAAkK5RZuVgAgAgANAAkK5RZuVgAgAgAAAA==.Lunafox:BAABNQAECn8rAAMCAAoKyRh1IQCfAgACAAoKyRh1IQCfAgANAAcK+An3dgAQAQAAAA==.Lunamae:BAABNQAECn8fAAIQAAkKDA7SzgDoAQAQAAkKDA7SzgDoAQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgoKTgABAJoeAA==.Luvvyyaa:BAABNQAECn9OAAQBAAoKmh5hJwCeAgABAAoKmh5hJwCeAgAhAAIKwQp8IABeAAAiAAEKdwkQXQA2AAAAAA==.Luvyya:BAAANQAECggIDAABNQAECgoKTgABAJoeAA==.',
Ly='Lythomancer:BAABNQAECn8fAAIaAAkK4QcAIQBpAQAaAAkK4QcAIQBpAQAAAA==.Lythoras:BAAANQAECgEIAQABNQAECgkJHwAaAOEHAA==.',
Ma='Maddeena:BAABNQAECn8bAAICAAgKuwdDkwDpAAACAAgKuwdDkwDpAAAAAA==.Magicmandunz:BAAANQAECgIIAgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFH8LAAILAAUKSxGYEQBzAQALAAUKSxGYEQBzAQA1AAQKfzEAAgsACQpUIq8ZACADAAsACQpUIq8ZACADAAAA.',
Mc='Mcmercie:BAABNQAECn8wAAMdAAoKMQ/3IwDBAQAdAAoKMQ/3IwDBAQADAAEKAADrygEAAAAAAA==.',
Me='Mechacooter:BAACNQAFFH8GAAIjAAMKlAiOCwB/AAAjAAMKlAiOCwB/AAA1AAQKfysAAiMACgrBGuMbAJ8CACMACgrBGuMbAJ8CAAAA.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECn8pAAIQAAgKHBLZhwCFAQAQAAgKHBLZhwCFAQAAAA==.Melchiorr:BAACNQAFFH8IAAIkAAIK2RB7BQCaAAAkAAIK2RB7BQCaAAA1AAQKfz8AAiQACgqoG5ICAPQCACQACgqoG5ICAPQCAAAA.Melynne:BAABNQAECn8uAAICAAoKExVrNAA1AgACAAoKExVrNAA1AgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECggIDgASAAAAAA==.Minji:BAABNQAECn8XAAIkAAgK1BlNCQDvAQAkAAgK1BlNCQDvAQABNQAECgkJHQABAIAhAA==.Minsoo:BAACNQAFFH8IAAIUAAIK8hhACACZAAAUAAIK8hhACACZAAA1AAQKfzoAAhQACgpSIQYDAKIDABQACgpSIQYDAKIDAAAA.',
Ml='Mlrgl:BAABNQAECn8qAAMgAAoKUCOLQwCgAgAgAAoKUCOLQwCgAgAWAAUK0xJ3RgAnAQAAAA==.Mlrglet:BAAANQAECggICgABNQAECgoKKgAgAFAjAA==.Mlrglo:BAAANQAECgUJBgABNQAECgoKKgAgAFAjAA==.',
Mo='Mormegil:BAABNQAECn8eAAQHAAoKrhYUKwDzAQAHAAoKPxMUKwDzAQAFAAUKbhnYagBIAQAGAAMKIx2kjADyAAAAAA==.Moshimoshi:BAACNQAFFH8NAAMCAAYK8Q4gEAA7AQACAAUKjgsgEAA7AQANAAEKAADwLwAAAAA1AAQKfx0AAwIACgpcFcxKADgCAAIACgpcFcxKADgCAA0AAwo6FeG4AIQAAAAA.Motosake:BAAANQADCgUIBQABNQAFFAYIDQACAPEOAA==.',
Mt='Mtx:BAAANQAECggIDgAAAA==.',
Mu='Muriana:BAAANQADCgYIBwAAAA==.',
My='Mythaera:BAAANQAECgQIBgAAAA==.',
Na='Naberius:BAABNQAECn8iAAQYAAkK5hUCDwDgAAAYAAUKkA0CDwDgAAAlAAcK1Q7AIgDbAAAZAAUKmREPFwC3AAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAABNQAECn8UAAIIAAkK7gmaOABKAQAIAAkK7gmaOABKAQABNQAFFAMIBgAjAJQIAA==.',
Ne='Nessará:BAABNQAECn9CAAIBAAoKgRX6LwBuAgABAAoKgRX6LwBuAgAAAA==.Newgate:BAAANQAECgQIBwAAAA==.',
Ni='Nightgodjuju:BAABNQAECn8tAAMPAAoKjBFSCgDiAQAPAAoKjBFSCgDiAQAQAAEKXwL7XgEmAAAAAA==.Nikna:BAAANQAECgUICwABNQAFFAYIEwAgABMcAA==.',
Nu='Nudacris:BAAANQAECggIEAABNQAECgoKKgAgAFAjAA==.Nuocbeo:BAAANQAECgEIAQAAAA==.Nuraga:BAABNQAECn8qAAMfAAgKPCNcBQAhAwAfAAgKPCNcBQAhAwAOAAEKcglrHgE3AAAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBQAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
Oc='Octari:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAABNQAECn8ZAAIWAAgK6BaBNQCiAQAWAAgK6BaBNQCiAQAAAA==.',
Pa='Pandaemonia:BAAANQAECgcIDQAAAA==.Pandakyle:BAABNQAECn8jAAIUAAkKxyC3BgArAwAUAAkKxyC3BgArAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECggIEgASAAAAAA==.Pattilicious:BAABNQAECn8VAAIDAAkKKQ3NvgCfAQADAAkKKQ3NvgCfAQAAAA==.',
Ph='Phonedin:BAABNQAECn8jAAMZAAoKZBdDFwDXAQAZAAcKhxdDFwDXAQAlAAgKXhbCGwApAQAAAA==.',
Pi='Pierres:BAAANQADCgMIAwAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECn8/AAMdAAoK0hjgDgAnAgAdAAoK0hjgDgAnAgADAAIK5gs9cAFuAAAAAA==.',
Pr='Protsucks:BAAANQAECgYIBgAAAA==.',
Py='Pyrug:BAAANQADCgYICwABNQAECgoKNwAaAK0aAA==.',
['Pá']='Pád:BAAANQAECgQIBwABNQAECgoKOAAgAFwSAA==.',
Qu='Quilue:BAAANQAECgcICwAAAA==.',
Ra='Rankak:BAAANQAECgIIAgABNQAFFAIICAAUAPIYAA==.Rannmagnison:BAABNQAECn8vAAIDAAgKuwYx6QBJAQADAAgKuwYx6QBJAQAAAA==.Raquoon:BAABNQAECn8cAAIfAAYKcQrqKAChAAAfAAYKcQrqKAChAAAAAA==.Rasonia:BAAANQAECgcIBwABNQAECgoKQAABAOcXAA==.Razzalghoul:BAABNQAECn8eAAMHAAgKDhIOPwDOAQAHAAgKDhIOPwDOAQAGAAQKEQd2qgChAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECggIFAAbAOoLAA==.Reuli:BAAANQAECgMICAAAAA==.Reze:BAABNQAECn8pAAIVAAoKhCN9DgD4AgAVAAoKhCN9DgD4AgABNQAFFAoKOgAIABkmAA==.',
Rh='Rhaeynera:BAABNQAECn8nAAIZAAcK0QQZFgDDAAAZAAcK0QQZFgDDAAAAAA==.Rhialle:BAAANQADCgQIBgABNQAECgEIAgASAAAAAA==.Rhinne:BAAANQAECgYICgAAAA==.',
Ri='Riezen:BAABNQAECn8sAAIGAAkKVBT+JgCWAQAGAAkKVBT+JgCWAQAAAA==.Rinorik:BAABNQAECn8pAAMLAAgKmB4JbwASAgALAAcKYh4JbwASAgAaAAIK3B+/QwC2AAAAAA==.',
Ro='Rockbiter:BAAANQAECgIIAgAAAA==.Rockhhard:BAAANQAECgMIBAAAAA==.Roeken:BAABNQAECn88AAIOAAoKFhNrTAAIAgAOAAoKFhNrTAAIAgAAAA==.Rollingman:BAAANQAECgYICwAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECn8rAAIFAAoKoyObFQAAAwAFAAoKoyObFQAAAwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECn8sAAIWAAoKjiC9CwB0AgAWAAoKjiC9CwB0AgAAAA==.',
Sa='Samsó:BAABNQAECn8zAAMMAAoKjRb3NgAsAgAMAAoKjRb3NgAsAgADAAEKAACoowE1AAAAAA==.Sapharina:BAABNQAECn9AAAMBAAoK5xe9SQD8AQABAAoK5xe9SQD8AQAiAAkK5Ag0HACbAQAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECn8sAAQbAAoKciC1CADHAgAbAAoKciC1CADHAgATAAcK8Bd5LAC4AQAXAAIKUg22UABgAAAAAA==.Schreckstoff:BAABNQAECn8qAAINAAkKrBQLXQALAgANAAkKrBQLXQALAgAAAA==.',
Se='Searfang:BAACNQAFFH8JAAINAAMKJBCREADbAAANAAMKJBCREADbAAA1AAQKfy0AAg0ACgozGts+AHoCAA0ACgozGts+AHoCAAAA.Sematic:BAABNQAECn8dAAMkAAoK/iDKAgCXAgAkAAgKeCHKAgCXAgALAAYKJxmSjgAqAQABNQAFFAcIGwAOAL0dAA==.Septik:BAAANQAECgEIAQAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAwAAAA==.Shadrielis:BAAANQAECgQIBAABNQAECgoKKgAgAFAjAA==.Shamor:BAAANQAECgYIDgAAAA==.Shashashmoo:BAABNQAECn8XAAIEAAcKvA2HVQCCAQAEAAcKvA2HVQCCAQAAAA==.Shlum:BAAANQAECgEIAQAAAA==.',
Si='Silaslunark:BAABNQAECn85AAIbAAoK0hfpCwD2AQAbAAoK0hfpCwD2AQAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skytec:BAAANQAECgIIAwAAAA==.Skëëts:BAAANQAECgIIAgAAAA==.',
Sl='Slampoof:BAAANQAECgEIAQAAAA==.Sleatsz:BAAANQAECgYIBgAAAA==.Sleez:BAAANQAECgQJBQAAAA==.Slime:BAAANQAECggICQAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBQASAAAAAA==.Smashmaster:BAAANQAECgQIDgAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIEQASAAAAAA==.',
Sn='Snowscayia:BAABNQAECn+AAAMTAAoKyCNBAwDFAwATAAoKyCNBAwDFAwAEAAgK4xVHNgA5AgAAAA==.Snypes:BAABNQAECn8aAAIEAAkKbBziIQC/AgAEAAkKbBziIQC/AgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECn8pAAIPAAgKYBtKCwAOAgAPAAgKYBtKCwAOAgAAAA==.',
Sq='Squadie:BAABNQAECn80AAIgAAoK4QpjdQC4AQAgAAoK4QpjdQC4AQAAAA==.Squanchs:BAACNQAFFH8MAAICAAQKXiRSCwCNAQACAAQKXiRSCwCNAQA1AAQKfysAAgIACgrcJeADAKwDAAIACgrcJeADAKwDAAE1AAQKBggIABIAAAAA.Squanchy:BAAANQAECgYICAAAAA==.',
Sr='Srry:BAAANQAECgcICQAAAA==.',
St='Stoot:BAAANQAECgMIBAABNQAECgUIFAAVABwkAA==.Stormdaka:BAAANQAECgEIAQABNQAECgoKLAAMAC8hAA==.Story:BAAANQADCgUIEAAAAA==.Sturm:BAAANQADCgEIAQAAAA==.Styrcius:BAABNQAECn8xAAIdAAkKrRxFDwAhAgAdAAkKrRxFDwAhAgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECggIEgAAAA==.Suniah:BAABNQAECn8VAAMfAAgKPwkMJQAdAQAfAAgKuwgMJQAdAQAOAAYKvgZ95wAWAQAAAA==.Surmise:BAAANQAECgEIAQABNQAFFAcIGwAOAL0dAA==.Sustmage:BAAANQAECgIIAgABNQAFFAcIGwAOAL0dAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQAECgIIAQAAAA==.Süß:BAAANQADCgIIAgABNQAECgoKLAAbAHIgAA==.',
Ta='Tabius:BAABNQAECn8UAAIbAAYKKBnXEwC/AQAbAAYKKBnXEwC/AQAAAA==.Talkingtaco:BAAANQAECgIICAAAAA==.Taln:BAAANQABCgEIAQABNQAECgoKHgAHAK4WAA==.',
Te='Tealle:BAAANQAECgEIAQABNQAECgkJIgAYAOYVAA==.Teddumby:BAAANQADCgcICAABNQAECgcIDwASAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAABNQAECn8YAAIDAAgKKAt+zwAjAQADAAgKKAt+zwAjAQAAAA==.',
Th='Thelorìn:BAABNQAECn8lAAIXAAkK8BsoDQCUAgAXAAkK8BsoDQCUAgAAAA==.Thiccdiq:BAABNQAECn8uAAMeAAkKQh1eBQA3AgAeAAgKXx5eBQA3AgAVAAQKFA66NADjAAAAAA==.Thiccgirl:BAAANQAECgEIAQAAAA==.Thirstycow:BAABNQAECn8aAAMCAAkKNQWvoAA1AQACAAkKNQWvoAA1AQANAAcKoAIpxwAEAQAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thornmar:BAAANQAECgQIEQAAAA==.Thosen:BAAANQAECggIEgAAAA==.',
Ti='Tinytina:BAAANQAECgQJBQAAAA==.',
To='Tore:BAABNQAECn9SAAIgAAoKCiYaBwBNAwAgAAoKCiYaBwBNAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAACNQAFFH8RAAIEAAUKBBJnEADgAAAEAAUKBBJnEADgAAA1AAQKfzAAAgQACgptHVAeANgCAAQACgptHVAeANgCAAAA.Tråitors:BAABNQAECn8kAAILAAgKZhP4oQCSAQALAAgKZhP4oQCSAQAAAA==.',
Ts='Tsarevich:BAABNQAECn8iAAIQAAcKowYB2QDnAAAQAAcKowYB2QDnAAAAAA==.',
Tw='Twileaf:BAABNQAECn8bAAITAAYKAgnTRgD7AAATAAYKAgnTRgD7AAAAAA==.',
['Té']='Térror:BAAANQADCgIIAgAAAA==.',
Ul='Ully:BAABNQAECn8UAAIRAAgKbRT0GADXAQARAAgKbRT0GADXAQAAAA==.',
Un='Unholyaltec:BAABNQAECn8eAAIGAAgKIhMCWQCsAQAGAAgKIhMCWQCsAQAAAA==.Unug:BAAANQADCggIDgABNQAECgoKNwAaAK0aAA==.',
Ut='Uthmansur:BAABNQAECn8kAAIcAAkKLgYOFwDzAAAcAAkKLgYOFwDzAAAAAA==.',
Va='Varkbyte:BAABNQAECn8iAAMBAAYKiRKZgwA1AQABAAYKiRKZgwA1AQAiAAEKAAAseAAAAAAAAA==.Varrik:BAABNQAECn8tAAMOAAgKsR8YUACZAgAOAAgKsR8YUACZAgAcAAEK0R3NMAA9AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECn8sAAMBAAoK8hlOKACYAgABAAoK8hlOKACYAgAhAAcKRA+2BwA5AQAAAA==.Volklin:BAABNQAECn8YAAICAAcKQAM3oADLAAACAAcKQAM3oADLAAAAAA==.Volyria:BAAANQADCgEIAQAAAA==.Voyageurs:BAACNQAFFH8FAAIbAAIK6w7aAgCGAAAbAAIK6w7aAgCGAAA1AAQKfykAAhsACgqQHUQHAO4CABsACgqQHUQHAO4CAAAA.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggIEgASAAAAAA==.Vyrka:BAABNQAECn8mAAIgAAcKoArltgApAQAgAAcKoArltgApAQAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBwABNQAECgoKQAAPAMgbAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgcIDwAAAA==.Werebear:BAAANQAECgUIBQABNQAECgUIBQASAAAAAA==.Werewithal:BAAANQADCgUIBQABNQAECgkJKgANAKwUAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgYICwAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBwABNQAECggIJAALAGYTAA==.Wheredergo:BAAANQAECgEIAgABNQAECgcIDwASAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Wiindsslashh:BAAANQAECgYIBwAAAA==.Windslash:BAAANQAECgEIAQAAAA==.Windsslashh:BAAANQAECgEIAgAAAA==.Wish:BAABNQAECn82AAMZAAoKPhqXBAB7AgAZAAoKPhqXBAB7AgAYAAYKahN5DwBIAQAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECgkJHQABAIAhAA==.Wonyoung:BAABNQAECn8dAAMBAAkKgCFPKADIAgABAAkKgCFPKADIAgAiAAEKsRJ4WAA+AAAAAA==.',
Wr='Wraithwok:BAAANQAECgMIBAAAAA==.Wråth:BAAANQAECgYIBgAAAA==.',
Wu='Wuthrad:BAAANQAECgcIEgAAAA==.',
Wy='Wyze:BAAANQAECgEIAQAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQAECgEIAgAAAA==.',
Xe='Xelienn:BAABNQAECn8rAAMHAAoKex6IIgB6AgAHAAoKex6IIgB6AgAGAAIKMAPW0wBGAAAAAA==.Xellor:BAAANQADCggIDgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAABNQAECn83AAIBAAoKMRyiHwDOAgABAAoKMRyiHwDOAgAAAA==.Xilhaunt:BAABNQAECn9OAAQaAAoK2R1TAgBKAgAaAAoKpRtTAgBKAgALAAoK8BluNQArAgAkAAQKShSnFQDwAAAAAA==.',
Xo='Xoilbiis:BAAANQAECgEIAQAAAA==.Xoilcast:BAAANQAECgMIAwAAAA==.Xoilkick:BAAANQAECggIEQAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAABNQAECn8WAAMKAAgKcRGMEQAaAQAKAAcKvxOMEQAaAQAIAAEK6AUbhAAqAAAAAA==.Xorm:BAAANQAECggIEAAAAA==.',
['Xê']='Xêna:BAABNQAECn8XAAIgAAkKWQfNkwBxAQAgAAkKWQfNkwBxAQAAAA==.',
['Xì']='Xì:BAAANQAECgEIAQAAAA==.',
Ya='Yaktac:BAAANQADCgIIAgAAAA==.',
Yb='Yb:BAAANQAECgYIDQABNQAECgoKVAAWALYhAA==.',
Ye='Yellowsnøw:BAAANQAECgUIBQAAAA==.Yenfina:BAAANQAECgEIAQAAAA==.',
Yu='Yumeshade:BAAANQAECgcIDgABNQAFFAYIDQACAPEOAA==.',
Za='Zaak:BAABNQAECn9EAAMmAAoKoSVYAABxAwAmAAoKoSVYAABxAwAgAAEK3yIgGwFmAAAAAA==.Zamari:BAABNQAECn8eAAINAAgK2wFutQCKAAANAAgK2wFutQCKAAAAAA==.Zanzabar:BAABNQAECn8XAAIbAAkKWA2MGQAnAQAbAAkKWA2MGQAnAQAAAA==.',
Ze='Zelfie:BAAANQAECgIIBAAAAA==.Zeliek:BAABNQAECn9JAAIMAAoKKCHIDABUAwAMAAoKKCHIDABUAwAAAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.Zeus:BAAANQADCgEIAQAAAA==.',
Zo='Zoerina:BAABNQAECn8dAAILAAoKqg+rTADbAQALAAoKqg+rTADbAQAAAA==.Zoobilong:BAABNQAECn8pAAIDAAoKQRJ9ggAjAgADAAoKQRJ9ggAjAgAAAA==.',
Zx='Zxak:BAAANQAECgQIBAABNQAECgoKRAAmAKElAA==.',
['Zë']='Zën:BAABNQAECn9EAAMQAAoKJA4SZADdAQAQAAoKJA4SZADdAQAPAAEKCQ8xTQAsAAAAAA==.',
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
