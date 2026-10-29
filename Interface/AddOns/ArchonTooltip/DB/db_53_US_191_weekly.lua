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

local lookup = {'Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Priest-Holy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Blood','Warlock-Affliction','Monk-Brewmaster','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Rogue-Assassination','Druid-Balance','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Priest-Discipline','DeathKnight-Unholy','Druid-Guardian',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acaciastrain:BAAANQADCggIDwAAAA==.',
Ad='Adorie:BAAANQAECgYIBgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAAANQAECgcIEgABNQAECgoKQgABAFAgAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn8nAAMCAAoKVRp4EwDFAgACAAoK4hl4EwDFAgADAAMK0hg88wBTAAABNQAECgoKQgABAFAgAA==.Aeón:BAAANQADCgMIAwABNQAECgUIEQAEAAAAAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAAANQAECgQIBAAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgUIAwAAAA==.Alkatractite:BAABNQAECn8bAAIFAAgKPRUubwB2AQAFAAgKPRUubwB2AQAAAA==.Allenwalker:BAAANQAECgYIDQAAAA==.Allison:BAAANQADCgUIBQABNQAECgoKNQAGAN8bAA==.',
Am='Amey:BAAANQAECgQIBgAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJJwAHAAoLAA==.',
Ao='Aoeslave:BAABNQAECn8vAAMIAAoK8hNjUAByAQAIAAkKDRNjUAByAQAJAAMKZRJQRwCqAAAAAA==.',
Ar='Arrisia:BAAANQAECgUIEgAAAA==.Arthedain:BAABNQAECn8tAAIKAAoK2SFJAwBsAwAKAAoK2SFJAwBsAwAAAA==.Arthedaine:BAACNQAFFH8HAAILAAQKBxCoAADcAAALAAQKBxCoAADcAAA1AAQKfyMAAgsACgrhG38BAKgCAAsACgrhG38BAKgCAAE1AAQKCgotAAoA2SEA.',
As='Assano:BAABNQAECn8bAAMJAAgKfw+0JABMAQAJAAYKWw+0JABMAQAIAAQKSgpOBAHDAAABNQAECgkJLwAMACAYAA==.',
Au='Autumni:BAAANQABCggIDQAAAA==.Auvry:BAABNQAECn8jAAINAAkKrQ/XGQAlAgANAAkKrQ/XGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggICAAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAABNQAECn8WAAIFAAYK7wjrugDlAAAFAAYK7wjrugDlAAAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgYIEgAEAAAAAA==.Bakala:BAABNQAECn8XAAMOAAYKrgb5GgD3AAAOAAYKrgb5GgD3AAAKAAIKwAEJTgAVAAAAAA==.Barath:BAAANQAECgYIEgAAAA==.',
Be='Beerwench:BAAANQAECgQIBAAAAA==.Belegaer:BAABNQAECn8jAAIPAAgKUQs8UQBTAQAPAAgKUQs8UQBTAQAAAA==.Belenos:BAAANQAECgEIAQABNQAECgEIAQAEAAAAAA==.Benmaverick:BAABNQAECn8ZAAIQAAkKtQ6cLgDMAQAQAAkKtQ6cLgDMAQAAAA==.Bervin:BAAANQAECgUIEQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8lAAIRAAgKbAr0VQBbAQARAAgKbAr0VQBbAQAAAA==.',
Bl='Bladesman:BAAANQAECggIDwAAAA==.',
Bo='Bobe:BAABNQAECn87AAIKAAoKmR/4BQAjAgAKAAoKmR/4BQAjAgAAAA==.Bobedruid:BAAANQAECgQIBAAAAA==.Bordok:BAABNQAECn8VAAISAAUKlQcCXgCoAAASAAUKlQcCXgCoAAAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAABNQAECn8rAAMDAAkKSBn/TACHAgADAAkKSBn/TACHAgACAAEK0QpxiQA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn81AAMTAAoKJhg2DwA3AgATAAoKJhg2DwA3AgAUAAYKBBjEFQCfAQAAAA==.',
Ce='Ceindra:BAACNQAFFH8FAAIVAAIKrg0TBACUAAAVAAIKrg0TBACUAAA1AAQKfywAAhUACgp/GM0KAMUCABUACgp/GM0KAMUCAAAA.Celestria:BAAANQAECgUIDAAAAA==.Celiñ:BAAANQAECgEIAQAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIDwAAAA==.Constantinez:BAAANQAECggIDgAAAA==.Cor:BAAANQAECgMIBAAAAA==.',
Cr='Crackerzz:BAAANQAECgYIBgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn84AAIWAAoKAhumKgBIAgAWAAoKAhumKgBIAgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8VAAMQAAUKBBoTCACAAQAQAAUKBBoTCACAAQAXAAEKdgB0FAAuAAA1AAQKfz0AAxAACgqVIOkNAAkDABAACgqVIOkNAAkDABcAAQoAADySADYAAAAA.David:BAABNQAECn8WAAIYAAgKlRr+YABrAgAYAAgKlRr+YABrAgAAAA==.',
De='Deadlyglow:BAABNQAECn8UAAMZAAgKyBlaPgAHAgAZAAcKfBhaPgAHAgASAAYKSBZDWABKAQAAAA==.Demiurgos:BAABNQAECn8XAAMGAAoKEhb1WwD7AQAGAAoKEhb1WwD7AQAMAAYKGAwSWQABAQAAAA==.Denji:BAAANQADCgQIBgAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8gAAQaAAkKNCCSCwCxAQAIAAgKaxtDfQDtAQAaAAYK7BuSCwCxAQAJAAIK9RzJSgCfAAAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAABNQAECn8tAAIYAAoK+QcOwAB9AQAYAAoK+QcOwAB9AQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8wAAIFAAkKdRaZcwBHAgAFAAkKdRaZcwBHAgAAAA==.',
Do='Dolemen:BAABNQAECn8cAAIFAAUKOQOgPAG/AAAFAAUKOQOgPAG/AAAAAA==.Domaon:BAABNQAECn8wAAIXAAkKuB78GADaAQAXAAkKuB78GADaAQAAAA==.Domshammy:BAAANQADCggICAABNQAECgkJMAAXALgeAA==.Doubt:BAAANQAECgUIDAAAAA==.Doughug:BAAANQAECgMIAwABNQAECgQIBAAEAAAAAA==.Dozy:BAABNQAECn8yAAIFAAoKlCPqCwAWAwAFAAoKlCPqCwAWAwAAAA==.',
Dr='Dracania:BAAANQADCgEIAQAAAA==.Druidheelzz:BAAANQAECgUICAAAAA==.Druissh:BAAANQAECgUIBwABNQAECgkJLwAMACAYAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn8hAAIFAAcKjg4I0AB7AQAFAAcKjg4I0AB7AQAAAA==.Dunigen:BAAANQAECgUICwAAAA==.',
Eb='Ebeast:BAABNQAECn8uAAILAAoKTxEcAwANAgALAAoKTxEcAwANAgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Fabulist:BAAANQADCgQIBAAAAA==.Facade:BAABNQAECn8fAAIZAAgKgwraNwAFAQAZAAgKgwraNwAFAQAAAA==.Facepalm:BAABNQAECn8eAAMOAAgKPBf+CQAwAgAOAAgKPBf+CQAwAgAYAAQKfwjaGgGmAAAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQAECgEIAQAAAA==.',
Fi='Fierytotes:BAAANQADCggIFAABNQAECggIDwAEAAAAAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAACNQAFFH8GAAIFAAMKLAtODwDLAAAFAAMKLAtODwDLAAA1AAQKfy8AAgUACQr6HiRNAK0CAAUACQr6HiRNAK0CAAAA.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgMIBAAAAA==.Foxmccloud:BAABNQAECn8YAAMGAAYKsxyDYwDjAQAGAAYKsxyDYwDjAQAMAAMKCwn4DgFuAAAAAA==.',
Fr='Fridge:BAAANQAECggICAABNQAECggICAAEAAAAAA==.Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECn8oAAIWAAgKNhibWQCgAQAWAAgKNhibWQCgAQAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAABNQAECn8rAAIFAAgKRgr+lgAlAQAFAAgKRgr+lgAlAQAAAA==.Gellywoo:BAABNQAECn8gAAIYAAkK0hGpSwCiAQAYAAkK0hGpSwCiAQAAAA==.Gemmarolizzy:BAAANQAECgQIBgAAAA==.Geneviève:BAAANQADCgQIBAAAAA==.',
Go='Golaoth:BAABNQAECn8bAAINAAYKehYUEABqAQANAAYKehYUEABqAQAAAA==.Gooftroupe:BAABNQAECn8nAAIPAAkKQCCUEwCrAgAPAAkKQCCUEwCrAgAAAA==.',
Gr='Grandmaster:BAABNQAECn8WAAIWAAgK3AgxkAAjAQAWAAgK3AgxkAAjAQABNQAECgEIAQAEAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAAANQAECgUIEwAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJLgAFAKIhAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAAANQAECgcIDwABNQAECggIHwAbAMYVAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgUICQAAAA==.',
He='Helbafx:BAAANQADCggIQwAAAA==.',
Hi='Hino:BAABNQAECn8XAAMRAAgKNBLCawDbAQARAAgKNBLCawDbAQAcAAEKDQf9RwA1AAAAAA==.',
Ho='Holywarriors:BAAANQAECgEIAQAAAA==.Homewrecker:BAABNQAECn8WAAIKAAYKPxZaHgBhAQAKAAYKPxZaHgBhAQAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Hu='Huské:BAAANQAECgIIAgAAAA==.',
Ic='Icebully:BAAANQAECgEIAQAAAA==.Icemàn:BAAANQADCgcICgAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
Is='Isabel:BAAANQAECgEIAgAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8UAAIGAAUK5B9kBADVAQAGAAUK5B9kBADVAQA1AAQKf1YAAgYACgpVJPsDAKMDAAYACgpVJPsDAKMDAAAA.Jakik:BAAANQADCgUICgAAAA==.Jakulista:BAAANQADCgEIAQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECggIDgAAAA==.',
Je='Jessuss:BAAANQAECgYIEAAAAA==.',
Jh='Jha:BAABNQAECn8YAAMdAAgKPR5eDAABAgAdAAcKPR5eDAABAgAXAAYKnhJKSwB1AQAAAA==.',
Ju='Jude:BAABNQAECn8iAAIFAAoKThYNdQBEAgAFAAoKThYNdQBEAgAAAA==.Junipermoon:BAAANQAECgEIAQAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAITAAgKkxHtKADYAQATAAgKkxHtKADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQABNQAFFAQIBQAIABQaAA==.Katotan:BAABNQAECn8tAAITAAkKBBXJJAD+AQATAAkKBBXJJAD+AQAAAA==.Kawk:BAAANQAECgMIAwAAAA==.',
Ke='Kealestra:BAABNQAECn8VAAIeAAUKGg6FHAALAQAeAAUKGg6FHAALAQAAAA==.Keyboärd:BAAANQAECgYIDQAAAA==.',
Ki='Kimochi:BAAANQAECgQIBAAAAA==.Kippo:BAEANQADCgcIBwABNQAECgcICAAEAAAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQADCgcIFQAAAA==.Kossnen:BAAANQAECgUIEgAAAA==.',
Kr='Krestisnack:BAABNQAECn8UAAIJAAUKjxahCwDDAAAJAAUKjxahCwDDAAAAAA==.',
Ku='Kuda:BAABNQAECn8eAAIeAAcKmxWJDgDCAQAeAAcKmxWJDgDCAQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUIDAAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgUIEQAEAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgUIEQAAAA==.',
La='Larke:BAAANQAECgEIAQAAAA==.Lasa:BAAANQAECgMIAgAAAA==.Lasloo:BAABNQAECn8rAAIFAAkKYA6IvQCiAQAFAAkKYA6IvQCiAQAAAA==.Laylani:BAABNQAECn8+AAIHAAoKQw/SEwBsAQAHAAoKQw/SEwBsAQAAAA==.',
Le='Lebronjames:BAAANQAECgUICgAAAA==.Leynreite:BAAANQAECgUICQAAAA==.',
Li='Lisan:BAABNQAECn8rAAIWAAkK6RASVACwAQAWAAkK6RASVACwAQAAAA==.Littledicey:BAABNQAECn8vAAIfAAoKWwrRIQD3AAAfAAoKWwrRIQD3AAAAAA==.',
Lu='Luciä:BAABNQAECn8bAAIZAAYKpg1nQADfAAAZAAYKpg1nQADfAAAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Lv='Lv:BAAANQAECggIEwAAAA==.',
Ly='Lykaios:BAAANQABCgQIBAAAAA==.Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8dAAIcAAgKdQxRMwCIAQAcAAgKdQxRMwCIAQAAAA==.Maerion:BAABNQAECn8ZAAMCAAYKagMLQABYAAADAAUK1gLNEwHdAAACAAYKkAILQABYAAAAAA==.Magdeth:BAAANQAECgcIEAAAAA==.Mantra:BAAANQAECgUIBQAAAA==.Maphra:BAAANQABCgUIBwAAAA==.Marabelle:BAABNQAECn8VAAIgAAgKwgWxXwBRAQAgAAgKwgWxXwBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Marrow:BAAANQADCgYIBgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8qAAIbAAgKkxXdBgCUAQAbAAgKkxXdBgCUAQAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJJwAHAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECggIHwAbAMYVAA==.Mero:BAABNQAECn8kAAMIAAoKMh5hMADGAgAIAAkKfx1hMADGAgAJAAIKHRnnSwCcAAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moiraine:BAAANQADCggICAAAAA==.Monkeywrench:BAAANQADCgIIAwAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Moonshiner:BAAANQAECgQIBAAAAA==.Moushuhan:BAABNQAECn8oAAMhAAkKrBT2GQAJAgAhAAkKVxT2GQAJAgAfAAIKqRLwiwCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAABNQAECn8cAAIWAAkKqhGyZACBAQAWAAkKqhGyZACBAQAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAACNQAFFH8KAAMiAAUKXhLRAQD7AAAiAAMKcRXRAQD7AAAfAAIKNgy8HABSAAA1AAQKfyUABCIACgrOJA0EANcCACIABwqtJA0EANcCAB8ABApRHgQyAKYAACEAAQrMJAmDAGoAAAAA.',
Nu='Nuke:BAAANQAECggICAAAAA==.',
Ny='Nytemayer:BAABNQAECn8gAAMIAAkKNRwmWQBLAgAIAAgKuxwmWQBLAgAJAAMKtRPnQwC1AAABNQAFFAMICQAQABUMAA==.Nytè:BAABNQAFFH8JAAIQAAMKFQwqBgDYAAAQAAMKFQwqBgDYAAAAAA==.',
Ob='Obmakare:BAABNQAECn8XAAIUAAYKrQoJIAAXAQAUAAYKrQoJIAAXAQAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgQIDQAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgQIBwAAAA==.Opiipal:BAAANQADCgIIAgAAAA==.Opiishift:BAABNQAECn8lAAIgAAoKQBbmMQBUAgAgAAoKQBbmMQBUAgAAAA==.Opiishots:BAAANQAECgQIDgAAAA==.',
Or='Orcc:BAAANQADCggIHQAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Peavey:BAAANQABCgEIAQAAAA==.Peligrosa:BAAANQAECggIDgABNQAECgEIAQAEAAAAAA==.Performance:BAABNQAECn82AAIdAAoKryJkAwAwAwAdAAoKryJkAwAwAwAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgAEAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBQAAAA==.Poîsonivy:BAABNQAECn8bAAIJAAYKwwnICgDLAAAJAAYKwwnICgDLAAAAAA==.',
Ps='Psyrine:BAAANQAECgUIBQAAAA==.',
Py='Pyrö:BAAANQAECggIEAAAAA==.',
Qu='Qu:BAABNQAECn85AAIYAAoKAR4/HwB4AgAYAAoKAR4/HwB4AgAAAA==.',
Ra='Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQADCggIMAAAAA==.Raymonnd:BAAANQADCgcICwAAAA==.',
Re='Reflektor:BAAANQABCgQIBAAAAA==.Renägäde:BAAANQAECggIEAAAAA==.Retiredfurry:BAABNQAECn8zAAMjAAoKciIlCAAPAwAjAAoKciIlCAAPAwABAAcKYx2yFgCGAQAAAA==.',
Ri='Ricodadawg:BAABNQAECn8+AAIWAAoKuCBqIABYAwAWAAoKuCBqIABYAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECgoKIwAMAPgLAA==.Runningshama:BAABNQAECn8jAAMMAAoK+AvVOgBpAQAMAAoK+AvVOgBpAQAGAAEK+hIyyQAzAAAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAABNQAECn8VAAIFAAUKAhvE0AB6AQAFAAUKAhvE0AB6AQAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAAANQAECgQICAAAAA==.Saintsnyder:BAABNQAECn8nAAQHAAkKCguoPgACAQAHAAUKKRaoPgACAQAFAAgKCQUHHAHwAAAPAAEKGgHgPQEPAAAAAA==.Saithis:BAAANQAECgEIAwAAAA==.Sanorasong:BAAANQAECgYIEgAAAA==.Saphaa:BAAANQAECgUIBQAAAA==.Saphirra:BAAANQADCggIEQAAAA==.Sarylin:BAAANQAECgQIBwAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECgcICAAAAA==.Sathpriest:BAABNQAECn8gAAQRAAoKNSIhDgBTAwARAAkKTyMhDgBTAwAkAAIKyRzxGACoAAAcAAEKAAD3ggAmAAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAAANQAECgUIEQAAAA==.',
Se='Severussnape:BAABNQAECn8qAAMIAAgKuQcUeQAGAQAIAAgKrAcUeQAGAQAJAAQKlwNjTQCXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.Sharpeyez:BAAANQAECgQIBAAAAA==.She:BAABNQAECn8oAAIhAAoK2BcWEAB7AgAhAAoK2BcWEAB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwABNQAFFAMIBQABALkUAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Simpmother:BAAANQAECgQIDAAAAA==.Sinensis:BAAANQAECgUICQAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAUIFQAQAAQaAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAABNQAECn8ZAAIlAAYKzRAaMgD9AAAlAAYKzRAaMgD9AAAAAA==.Skinalittleb:BAAANQAECgQIBAAAAA==.',
Sl='Slaycie:BAABNQAECn8ZAAIRAAgKihd6NADpAQARAAgKihd6NADpAQAAAA==.',
Sn='Sneek:BAAANQAECgUIDgAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgUIDgAAAA==.',
Sp='Spaghett:BAABNQAECn8fAAMbAAgKxhUICgA1AQAbAAgKxhUICgA1AQABAAYKWAb8VQCUAAAAAA==.',
St='Stanger:BAABNQAECn8XAAIGAAkKax7oKADAAgAGAAkKax7oKADAAgAAAA==.Starlight:BAABNQAECn8fAAIgAAoKSh05CgCrAgAgAAoKSh05CgCrAgABNQAECgkJNgAFANokAA==.Stonefly:BAAANQAECgEIAQAAAA==.',
Sy='Syrden:BAABNQAECn8yAAITAAoKMA6gKgDJAQATAAoKMA6gKgDJAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn8tAAIOAAkKrR4/BAA5AgAOAAkKrR4/BAA5AgAAAA==.Tangylizard:BAABNQAECn8bAAMRAAkKHSBwEQDgAgARAAkK/R9wEQDgAgAkAAUKoxSEDwAzAQAAAA==.Tawainai:BAABNQAECn8tAAIWAAgKFhJZcwBeAQAWAAgKFhJZcwBeAQAAAA==.',
Te='Tessla:BAABNQAECn8vAAMMAAkKIBjMLQClAQAMAAkKIBjMLQClAQAGAAIKtQGtFgE9AAAAAA==.Tetragram:BAABNQAECn9CAAIBAAoKUCCEBQDaAgABAAoKUCCEBQDaAgAAAA==.',
Th='Thelarï:BAABNQAECn8qAAIDAAgKBgnoqgCvAQADAAgKBgnoqgCvAQAAAA==.Thors:BAABNQAECn8uAAIFAAkKoiHHEwB3AwAFAAkKoiHHEwB3AwAAAA==.Thundertoes:BAABNQAECn8oAAMGAAgKsBdkQgCNAQAGAAgKsBdkQgCNAQAMAAUKDw0KuAAiAQAAAA==.',
Ti='Tia:BAAANQADCgEIAQAAAA==.Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAABNQAECn8XAAMlAAYK8RWbZAB+AQAlAAYK8RWbZAB+AQASAAEKTwiIuAAmAAAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAABNQAECn8bAAMMAAcKiBCXqABDAQAMAAYKSQ6XqABDAQAGAAUKmwyV1AC+AAAAAA==.Torgoth:BAABNQAECn8bAAIVAAYKaAlZGAALAQAVAAYKaAlZGAALAQAAAA==.Toshido:BAAANQAECgYIEQAAAA==.Totemtroller:BAAANQAECgEIAQAAAA==.Toy:BAAANQAECgMIAwAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECgQIDAAAAA==.',
Un='Unholypally:BAAANQADCggIFwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn85AAMFAAoK1xvzPgDYAgAFAAoK1xvzPgDYAgAPAAcKOQQTrwAhAQAAAA==.Valiantaint:BAABNQAECn8kAAIQAAkKSBjUHgBZAgAQAAkKSBjUHgBZAgABNQAECgoKOQAFANcbAA==.Valiantroar:BAAANQAECgYIBgABNQAECgoKOQAFANcbAA==.Vashon:BAAANQADCgQIBgAAAA==.',
Ve='Velherun:BAABNQAECn8iAAIFAAgKDxUYnADqAQAFAAgKDxUYnADqAQAAAA==.Vendel:BAABNQAECn8sAAIMAAkK7yQCBwCxAwAMAAkK7yQCBwCxAwAAAA==.Vexxaa:BAABNQAECn8bAAIDAAYKoAxdgwArAQADAAYKoAxdgwArAQAAAA==.',
Vi='Virajr:BAAANQAECgQICQAAAA==.Vissiction:BAABNQAECn8gAAIQAAgKIRWGFwB+AQAQAAgKIRWGFwB+AQAAAA==.Vistine:BAABNQAECn8WAAIHAAYKsghlMACVAAAHAAYKsghlMACVAAABNQAECgkJLwAMACAYAA==.Vitez:BAABNQAECn8WAAIIAAgKegiCtgBhAQAIAAgKegiCtgBhAQAAAA==.',
Wa='Waterslide:BAAANQADCgYIDgAAAA==.',
We='Weatherman:BAAANQADCgQIBAAAAA==.Wendy:BAABNQAECn81AAIGAAoK3xtQMADiAQAGAAoK3xtQMADiAQAAAA==.',
Wh='Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAABNQAECn8cAAMTAAcKCwkgPQA6AQATAAcKCwkgPQA6AQAgAAcKxAwfMQAOAQABNQAECggICAAEAAAAAA==.Winkster:BAAANQAECgcIDwAAAA==.',
Xa='Xanadu:BAABNQAECn8yAAMkAAoK2h7WAAD6AgAkAAoK2h7WAAD6AgARAAEKUxLD/AAyAAAAAA==.Xarinia:BAAANQAECgIIAgABNQAECgoKOwASAMEMAA==.',
Xb='Xbear:BAABNQAECn8bAAImAAYK/hSbHwAMAQAmAAYK/hSbHwAMAQABNQAFFAUIFwAhAMgZAA==.',
Xd='Xdynasty:BAACNQAFFH8XAAMhAAUKyBnPCQABAQAhAAUKyBnPCQABAQAfAAEKpBtjCwBQAAA1AAQKfz0AAyEACgoBIvoHAPoCACEACgpHH/oHAPoCAB8ABAqmHqBXAFwBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgYIDQAEAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAECggICAAEAAAAAA==.',
Za='Zabazz:BAABNQAECn8mAAMGAAgKyhBrNQDIAQAGAAgKyhBrNQDIAQAMAAEKAADjXgEaAAAAAA==.Zabenir:BAABNQAECn8WAAIcAAYKWxW2GQBDAQAcAAYKWxW2GQBDAQAAAA==.Zalrote:BAAANQADCggICgABNQAECgoKOwASAMEMAA==.Zaraina:BAABNQAECn8aAAIRAAYKOxM/ZwAhAQARAAYKOxM/ZwAhAQABNQAFFAUIFQAQAAQaAA==.',
Ze='Zerototem:BAABNQAECn8rAAMGAAgKyBeTTQAtAgAGAAgKyBeTTQAtAgAMAAIKGAlsEQFpAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAUIFQAQAAQaAA==.',
['Çu']='Çuddleybunny:BAAANQADCgUIBQAAAA==.',
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
