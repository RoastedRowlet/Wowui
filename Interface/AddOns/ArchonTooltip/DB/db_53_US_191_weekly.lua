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

local lookup = {'DeathKnight-Frost','Monk-Windwalker','Hunter-Marksmanship','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Evoker-Preservation','Warrior-Fury','Paladin-Holy','DemonHunter-Devourer','Priest-Holy','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Blood','Warlock-Affliction','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','Priest-Shadow','Mage-Frost','Rogue-Assassination','DeathKnight-Unholy','Druid-Balance','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acaciastrain:BAAANQADCggIDwAAAA==.',
Ad='Adorie:BAAANQAECgYIBgAAAA==.',
Ae='Aelord:BAAANQADCgUIBQAAAA==.Aerebos:BAABNQAECn8cAAIBAAoK6RAeJwDjAQABAAoK6RAeJwDjAQABNQAECgoKUQACAE4kAA==.Aeriss:BAAANQABCgQIBAAAAA==.Aetheria:BAAANQADCgYJBgAAAA==.Aethos:BAABNQAECn8uAAMDAAoK9hpmDABNAgADAAoK9hpmDABNAgAEAAMK0hjLNwF3AAABNQAECgoKUQACAE4kAA==.Aeón:BAAANQADCgMIAwABNQAECgUIEQAFAAAAAA==.',
Ag='Agua:BAAANQAECgQIBAAAAA==.',
Ak='Akashá:BAAANQAECgcICgAAAA==.',
Al='Aladrius:BAEANQAECgQIBwAAAA==.Alexanderath:BAAANQAECgUIAwAAAA==.Alkatractite:BAABNQAECn8eAAIGAAkK4hU/cACvAQAGAAkK4hU/cACvAQAAAA==.Allenwalker:BAAANQAECgYIDQAAAA==.Allison:BAAANQADCgUIBQABNQAECgoKOgAHAN8bAA==.',
Am='Amey:BAAANQAECgYICwAAAA==.',
An='Anelise:BAAANQADCgUIBQAAAA==.Antelon:BAAANQAECgMIAwABNQAECgkJJwAIAAoLAA==.',
Ao='Aoeslave:BAACNQAFFH8FAAMJAAMK3wSEJQBuAAAJAAIKZwWEJQBuAAAKAAEKzgO+EgA/AAA1AAQKfzEAAwkACgpKFTVmAGkBAAkACQqXFDVmAGkBAAoAAwplElBHAKoAAAAA.',
Ar='Arrisia:BAABNQAECn8bAAIEAAYKlAYm3wBCAQAEAAYKlAYm3wBCAQAAAA==.Arthedain:BAABNQAECn81AAILAAoKwSJJAwBsAwALAAoKwSJJAwBsAwAAAA==.Arthedaine:BAACNQAFFH8HAAIMAAQKBxDtAADYAAAMAAQKBxDtAADYAAA1AAQKfyoAAgwACgomHskBAL4CAAwACgomHskBAL4CAAE1AAQKCgo1AAsAwSIA.',
As='Assano:BAABNQAECn8bAAMKAAgKfw+0JABMAQAKAAYKWw+0JABMAQAJAAQKSgpOBAHDAAABNQAECgoKMwANALsWAA==.',
Au='Autumni:BAAANQADCgYIBgAAAA==.Auvry:BAABNQAECn8jAAIOAAkKrQ/XGQAlAgAOAAkKrQ/XGQAlAgAAAA==.',
Az='Azliain:BAAANQAECggIDAAAAA==.Azurine:BAAANQADCgYIBgAAAA==.',
Ba='Bahamutfang:BAABNQAECn8XAAIGAAYK7wju3wDgAAAGAAYK7wju3wDgAAAAAA==.Bahozakurkho:BAAANQAECgMIAwABNQAECgYIEwAFAAAAAA==.Bakala:BAABNQAECn8dAAMPAAYK5Ab5GgD3AAAPAAYK5Ab5GgD3AAALAAIKwAEJTgAVAAAAAA==.Barath:BAAANQAECgYIEwAAAA==.',
Be='Beerwench:BAAANQAECgUICQAAAA==.Belegaer:BAABNQAECn8lAAIQAAgKkwu6ZwBNAQAQAAgKkwu6ZwBNAQAAAA==.Belenos:BAAANQAECgEIAQABNQAECgEIAQAFAAAAAA==.Benmaverick:BAABNQAECn8cAAIRAAkKtQ6cLgDMAQARAAkKtQ6cLgDMAQAAAA==.Bervin:BAAANQAECgUIEQAAAA==.',
Bi='Bifftunkisjr:BAAANQADCgEJAQAAAA==.Bishop:BAABNQAECn8sAAISAAkK0Am0YQB/AQASAAkK0Am0YQB/AQAAAA==.',
Bl='Bladesman:BAAANQAECggIDwAAAA==.',
Bo='Bobe:BAABNQAECn9FAAILAAoK2CACAwD4AgALAAoK2CACAwD4AgAAAA==.Bobedruid:BAAANQAECgQIBAAAAA==.Bordok:BAABNQAECn8WAAIBAAUKlQdPcQCjAAABAAUKlQdPcQCjAAAAAA==.Borkuz:BAAANQADCggJCAAAAA==.',
Br='Brawl:BAAANQADCgYIBgAAAA==.Brunco:BAABNQAECn8vAAMEAAoKJRn/TACHAgAEAAoKJRn/TACHAgADAAEK0QpxiQA1AAAAAA==.',
Ca='Captplanet:BAABNQAECn83AAMTAAoKJhh/FAClAgATAAoKJhh/FAClAgAUAAYKBBjEFQCfAQAAAA==.',
Ce='Ceindra:BAACNQAFFH8HAAIVAAQKgg18AwDYAAAVAAQKgg18AwDYAAA1AAQKfy0AAhUACgonGs0KAMUCABUACgonGs0KAMUCAAAA.Celestria:BAAANQAECgUIEAAAAA==.Celiñ:BAAANQAECgUIBgAAAA==.Cerealkiller:BAAANQADCgYJBgAAAA==.',
Ch='Chipcho:BAAANQADCggICAAAAA==.Chockula:BAAANQADCgMIAwAAAA==.Chuladk:BAAANQAECgEIAQAAAA==.',
Co='Colbalt:BAAANQADCggIDwAAAA==.Constantinez:BAABNQAECn8XAAIKAAoKIQJ6QwC3AAAKAAoKIQJ6QwC3AAAAAA==.Cor:BAAANQAECgMIBAAAAA==.',
Cr='Crackerzz:BAAANQAECgYICgAAAA==.',
Cu='Cuddlymethod:BAAANQADCgYICQAAAA==.',
['Có']='Cól:BAABNQAECn87AAIWAAoKAhssOQBAAgAWAAoKAhssOQBAAgAAAA==.Cónky:BAAANQADCgcIBQAAAA==.',
Da='Daddymoo:BAAANQADCgUIDAAAAA==.Dahealzrhere:BAAANQADCgEIAQAAAA==.Dalel:BAACNQAFFH8aAAMRAAYKOxlMBAAdAQARAAYKOxlMBAAdAQAXAAEKdgCBGAAuAAA1AAQKf0EAAxEACgqVIOkNAAkDABEACgqVIOkNAAkDABcAAQoAADySADYAAAAA.David:BAABNQAECn8WAAIYAAgKlRr+YABrAgAYAAgKlRr+YABrAgAAAA==.',
De='Deadlyglow:BAABNQAECn8aAAMZAAgKpxpaPgAHAgAZAAcK7BhaPgAHAgABAAYKDBdDWABKAQAAAA==.Demiurgos:BAABNQAECn8XAAMHAAoKEhb1WwD7AQAHAAoKEhb1WwD7AQANAAYKGAwNcwD3AAAAAA==.Denji:BAAANQADCggIBgAAAA==.Denogarn:BAAANQADCggIEQAAAA==.Dermot:BAABNQAECn8jAAQaAAkKViCSCwCxAQAJAAgK7RxDfQDtAQAaAAYK7BuSCwCxAQAKAAIK9RzJSgCfAAAAAA==.',
Dh='Dhiying:BAAANQADCgcIBwAAAA==.',
Di='Dirtface:BAABNQAECn83AAIYAAoK+QcifABZAQAYAAoK+QcifABZAQAAAA==.Dixlongmd:BAAANQAECgEIAQAAAA==.Dixmen:BAABNQAECn8wAAIGAAkKdRaZcwBHAgAGAAkKdRaZcwBHAgAAAA==.',
Do='Dolemen:BAABNQAECn8iAAIGAAcKrAN9BQGoAAAGAAcKrAN9BQGoAAAAAA==.Domaon:BAABNQAECn86AAIXAAoKKCDqCwDAAgAXAAoKKCDqCwDAAgAAAA==.Domshammy:BAAANQADCggICAABNQAECgoKOgAXACggAA==.Doubt:BAAANQAECgUIDAAAAA==.Doughug:BAAANQAECgMIAwABNQAECgQIBAAFAAAAAA==.Dozy:BAABNQAECn84AAIGAAoKmiNkDgAfAwAGAAoKmiNkDgAfAwAAAA==.',
Dr='Dracania:BAAANQADCgEIAQAAAA==.Druidheelzz:BAAANQAECgUICAAAAA==.Druissh:BAAANQAECgQICAABNQAECgoKMwANALsWAA==.Drôôdude:BAAANQADCgQIBAAAAA==.',
Du='Dullgrim:BAAANQADCggICAAAAA==.Dunigan:BAABNQAECn8hAAIGAAcKjg4I0AB7AQAGAAcKjg4I0AB7AQAAAA==.Dunigen:BAAANQAECgUIEAAAAA==.',
Eb='Ebeast:BAABNQAECn84AAIMAAoKTxE0BAAUAgAMAAoKTxE0BAAUAgAAAA==.',
Ef='Efel:BAAANQADCggICAAAAA==.',
Ev='Evianda:BAAANQADCggIEAAAAA==.',
Fa='Fabulist:BAAANQADCgQIBAAAAA==.Facade:BAABNQAECn8fAAIZAAgKgwqrRQD9AAAZAAgKgwqrRQD9AAAAAA==.Facepalm:BAABNQAECn8eAAMPAAgKPBf+CQAwAgAPAAgKPBf+CQAwAgAYAAQKfwjaGgGmAAAAAA==.Falyy:BAAANQADCgMIAwAAAA==.Farmergeorge:BAAANQAECgQJCAAAAA==.',
Fe='Fentak:BAAANQAECgEIAQAAAA==.',
Fi='Fierytotes:BAAANQADCggIFAABNQAECggIDwAFAAAAAA==.Finnek:BAAANQADCgMIAwAAAA==.',
Fo='Forbidenelf:BAACNQAFFH8KAAIGAAQKEQ6TEgDPAAAGAAQKEQ6TEgDPAAA1AAQKfzgAAgYACQpwIXIfAMMCAAYACQpwIXIfAMMCAAAA.Forging:BAAANQADCgQIBAAAAA==.Forgotmymeds:BAAANQAECgQICAAAAA==.Foxmccloud:BAABNQAECn8eAAMHAAYKjiKZNQAUAgAHAAYKjiKZNQAUAgANAAMKCwn4DgFuAAAAAA==.',
Fr='Fridge:BAAANQAFFAEIAQAAAA==.Frosted:BAAANQADCggIAgAAAA==.Fruitloop:BAABNQAECn8qAAIWAAgKNhjBdQCSAQAWAAgKNhjBdQCSAQAAAA==.',
Fu='Funkybooty:BAAANQABCgIIAgAAAA==.Fuzybrewing:BAAANQABCgQICAAAAA==.',
Ga='Garidrael:BAAANQABCgMIAwAAAA==.',
Ge='Gebran:BAABNQAECn8yAAIGAAgKRgrhwgAQAQAGAAgKRgrhwgAQAQAAAA==.Gellywoo:BAABNQAECn8sAAIYAAoKtxR7QgAMAgAYAAoKtxR7QgAMAgAAAA==.Gemmarolizzy:BAAANQAECgQIBgAAAA==.Geneviève:BAAANQADCgQIBAAAAA==.',
Go='Golaoth:BAABNQAECn8cAAIOAAYK1hbZEgCLAQAOAAYK1hbZEgCLAQAAAA==.Gooftroupe:BAABNQAECn8pAAIQAAkKQCD8HgCVAgAQAAkKQCD8HgCVAgAAAA==.',
Gr='Grandmaster:BAABNQAECn8WAAIWAAgK3AgosQAYAQAWAAgK3AgosQAYAQABNQAECgEIAQAFAAAAAA==.Grawn:BAAANQADCgMIAwAAAA==.Greymoon:BAABNQAECn8cAAIbAAYKaBWMKwD3AAAbAAYKaBWMKwD3AAAAAA==.Grimaced:BAAANQAECgYIBgABNQAECgkJOAAGAKYjAA==.Grimtotems:BAAANQADCgMIAwAAAA==.',
Ha='Haezi:BAABNQAECn8XAAQcAAgKJxcGCwBwAQAcAAcKJxcGCwBwAQAXAAUKIxKGWgAbAQARAAEKAAAGcgArAAABNQAECggIIQAdAMYVAA==.Haki:BAAANQABCgIIAgAAAA==.Hammerbully:BAAANQADCgEIAQAAAA==.Happyendings:BAAANQAECgYICQAAAA==.',
He='Helbafx:BAAANQADCggIQwAAAA==.',
Hi='Hino:BAABNQAECn8XAAMSAAgKNBLCawDbAQASAAgKNBLCawDbAQAeAAEKDQcGVwAyAAAAAA==.',
Ho='Holywarriors:BAAANQAECgQIBQAAAA==.Homewrecker:BAABNQAECn8cAAILAAYKPxZaHgBhAQALAAYKPxZaHgBhAQAAAA==.Horuid:BAAANQADCgEIAQAAAA==.',
Hu='Huntzman:BAAANQADCgUIBQAAAA==.Huské:BAAANQAECgIIAgAAAA==.',
Ic='Icebully:BAAANQAECgIIAgAAAA==.Icemàn:BAAANQAECgQIBAAAAA==.',
Id='Idrazil:BAAANQAECgcIEAAAAA==.',
If='Ifearnobeer:BAAANQAECgMIBAAAAA==.',
In='Infectz:BAAANQAECggJAgAAAA==.Infoxicated:BAAANQADCgQIBAAAAA==.',
Is='Isabel:BAAANQAECgEIAgAAAA==.',
It='Itburnsalot:BAAANQADCgYIBgAAAA==.',
Ja='Jaiantobea:BAACNQAFFH8ZAAIHAAYKax/uAwAoAgAHAAYKax/uAwAoAgA1AAQKf1sAAwcACgpVJH0GAJUDAAcACgpVJH0GAJUDAA0AAQrjFLDQAEMAAAAA.Jakik:BAAANQADCgUICgAAAA==.Jakulista:BAAANQADCgEIAQAAAA==.Jarlaxl:BAAANQADCgQIBAAAAA==.Jawn:BAAANQAECggIDgAAAA==.',
Je='Jessuss:BAAANQAECgYIEwAAAA==.',
Jh='Jha:BAABNQAECn8YAAMcAAgKPR5eDAABAgAcAAcKPR5eDAABAgAXAAYKnhJKSwB1AQAAAA==.',
Ju='Jude:BAABNQAECn8kAAIGAAoKThYNdQBEAgAGAAoKThYNdQBEAgAAAA==.Junipermoon:BAAANQAECgEIAQAAAA==.',
Ka='Kabub:BAAANQAECgYIEQAAAA==.Kalahandra:BAABNQAECn8bAAITAAgKkxHtKADYAQATAAgKkxHtKADYAQAAAA==.Kalebeesd:BAAANQADCgUIBwAAAA==.Katablight:BAAANQAECggIEQABNQAFFAUIBgAJABQaAA==.Katotan:BAABNQAECn8wAAITAAkK1xXJJAD+AQATAAkK1xXJJAD+AQAAAA==.Kawk:BAAANQAECgMIAwAAAA==.',
Ke='Kealestra:BAABNQAECn8WAAIfAAUKGg6FHAALAQAfAAUKGg6FHAALAQAAAA==.Keyboärd:BAAANQAECgYIDwAAAA==.',
Ki='Kimochi:BAAANQAECgQIBAAAAA==.Kippo:BAEANQADCgcIBwABNQAECgcICAAFAAAAAA==.Kittylover:BAAANQAECgIIAgAAAA==.',
Ko='Kombat:BAAANQADCgYJCgAAAA==.Korllan:BAAANQAECgEIAQAAAA==.Kossnen:BAAANQAECgUIEgAAAA==.',
Kr='Krestisnack:BAABNQAECn8UAAIKAAUKjxZ1IgBdAQAKAAUKjxZ1IgBdAQAAAA==.',
Ku='Kuda:BAABNQAECn8lAAIfAAgKjBSJDgDCAQAfAAgKjBSJDgDCAQAAAA==.Kullkil:BAAANQADCggIEQAAAA==.',
Kw='Kwanu:BAAANQAECgUIDAAAAA==.',
['Kñ']='Kño:BAAANQADCgMIAwABNQAECgUIEQAFAAAAAA==.',
['Kó']='Kóñä:BAAANQAECgUIEQAAAA==.',
La='Larke:BAAANQAECgEIAQAAAA==.Lasa:BAAANQAECgMIAgAAAA==.Lasloo:BAABNQAECn80AAIGAAoKmhDqbAC3AQAGAAoKmhDqbAC3AQAAAA==.Laylani:BAABNQAECn9CAAIIAAoKchLPFgCPAQAIAAoKchLPFgCPAQAAAA==.',
Le='Lebronjames:BAAANQAECgUICgAAAA==.Leynreite:BAAANQAECgUICQAAAA==.',
Li='Lisan:BAABNQAECn8xAAIWAAkKFRO1ZAC/AQAWAAkKFRO1ZAC/AQAAAA==.Littledicey:BAABNQAECn84AAIgAAoKtgscEQCXAQAgAAoKtgscEQCXAQAAAA==.',
Lu='Luciä:BAABNQAECn8cAAIZAAYKpg3GTgDZAAAZAAYKpg3GTgDZAAAAAA==.Lucymoon:BAAANQAECgYIBgAAAA==.Luvflap:BAAANQADCgMIAwAAAA==.',
Lv='Lv:BAABNQAECn8YAAMbAAkK2w9YIwAwAQAbAAkKcw1YIwAwAQAUAAIKIxHJKwBwAAABNQAECgoKHgAhAKMfAA==.',
Ly='Lykaios:BAAANQABCgQIBAAAAA==.Lyñx:BAAANQADCgQIBgAAAA==.',
Ma='Machoman:BAAANQAECgQIBAAAAA==.Madness:BAABNQAECn8hAAIeAAoKKgxRMwCIAQAeAAoKKgxRMwCIAQAAAA==.Maerion:BAABNQAECn8aAAMDAAYKagPVawB+AAAEAAUK1gLNEwHdAAADAAYKkALVawB+AAAAAA==.Magdeth:BAABNQAECn8YAAINAAgKmRCCUwArAgANAAgKmRCCUwArAgAAAA==.Mantra:BAAANQAECgUIBQAAAA==.Maphra:BAAANQABCgUIBwAAAA==.Marabelle:BAABNQAECn8XAAIiAAgKuAaxXwBRAQAiAAgKuAaxXwBRAQAAAA==.Marasteil:BAAANQADCgIIAgAAAA==.Mariomage:BAAANQADCgQICAAAAA==.Marixia:BAAANQAECgUICgAAAA==.Marrow:BAAANQADCgYIBgAAAA==.Masilitu:BAAANQADCgYIDwAAAA==.Massack:BAABNQAECn8sAAIdAAgKDRZzCQCAAQAdAAgKDRZzCQCAAQAAAA==.Mawgwa:BAAANQAECgMIAwAAAA==.',
Mc='Mcwrath:BAAANQADCgcIDQABNQAECgkJJwAIAAoLAA==.',
Me='Meeow:BAAANQADCgEIAQABNQAECggIIQAdAMYVAA==.Mero:BAABNQAECn8oAAQJAAoKSB5hMADGAgAJAAkKmB1hMADGAgAKAAIKHRnnSwCcAAAaAAEKSQp+JQA4AAAAAA==.',
Mi='Midgetmàniàc:BAAANQADCggICAAAAA==.',
Mo='Moiraine:BAAANQAECgQIBAAAAA==.Monkeywrench:BAAANQADCgIIAwAAAA==.Moobear:BAAANQADCgUIBQAAAA==.Moonshiner:BAAANQAECgQIBAAAAA==.Moushuhan:BAABNQAECn8oAAMjAAkKrBT2GQAJAgAjAAkKVxT2GQAJAgAgAAIKqRLwiwCBAAAAAA==.',
My='Mystrall:BAAANQAECgQIBAAAAA==.',
Na='Naanaa:BAABNQAECn8cAAIWAAkKqhF9gwBzAQAWAAkKqhF9gwBzAQAAAA==.Nadorian:BAAANQABCgIIAgAAAA==.Narey:BAAANQADCgIIAgAAAA==.',
Ne='Neb:BAAANQAECgEIAQAAAA==.Netherrogue:BAACNQAFFH8MAAQkAAYKHRLRAQD7AAAkAAMKcRXRAQD7AAAjAAIKWxE5HABdAAAgAAIKNgy8HABSAAA1AAQKfyYABCQACgrOJA0EANcCACQABwqtJA0EANcCACAABApRHiM4AJwAACMAAQrMJAaiAGsAAAAA.',
Nu='Nuke:BAAANQAECggICwABNQAFFAEIAQAFAAAAAA==.',
Ny='Nytemayer:BAABNQAECn8gAAMJAAkKNRwmWQBLAgAJAAgKuxwmWQBLAgAKAAMKtRPnQwC1AAABNQAFFAQICgARABUMAA==.Nytè:BAACNQAFFH8KAAIRAAQKFQzFBwDRAAARAAQKFQzFBwDRAAA1AAQKfxsAAhEACApqFtAsANsBABEACApqFtAsANsBAAAA.',
Ob='Obmakare:BAABNQAECn8ZAAMUAAYKrQoJIAAXAQAUAAYKrQoJIAAXAQATAAEKrAZscwAcAAAAAA==.Obonhigh:BAAANQADCgEIAQAAAA==.Oboñ:BAAANQAECgUIEgAAAA==.Obsfuyung:BAAANQAECgUICgAAAA==.',
Oo='Oopsiez:BAAANQAECgQIBgAAAA==.',
Op='Opiiknight:BAAANQAECgQIBwAAAA==.Opiipal:BAAANQADCgIIAgAAAA==.Opiishift:BAACNQAFFH8GAAIiAAMKSQaAEQC6AAAiAAMKSQaAEQC6AAA1AAQKfygAAiIACgqfF+YxAFQCACIACgqfF+YxAFQCAAAA.Opiishots:BAABNQAECn8aAAIEAAoKtxUAMwBJAgAEAAoKtxUAMwBJAgAAAA==.',
Or='Orcc:BAAANQADCggIHQAAAA==.',
Pa='Paley:BAAANQAECgQICAAAAA==.',
Pd='Pdgrimm:BAAANQADCgQIBAAAAA==.',
Pe='Peavey:BAAANQABCgEIAQAAAA==.Peligrosa:BAAANQAECggIDgABNQAECgEIAQAFAAAAAA==.Performance:BAABNQAECn87AAQcAAoKryJkAwAwAwAcAAoKryJkAwAwAwARAAMKPRLJPQCDAAAXAAEKBBWObQBEAAAAAA==.Peterturbo:BAAANQAECgQICAABNQABCgIIAgAFAAAAAA==.',
Pi='Pinkky:BAAANQADCgcIBwAAAA==.',
Po='Pocketfox:BAAANQAECgMIBQAAAA==.Poisonoak:BAAANQABCgIIAgAAAA==.Poîsonivy:BAABNQAECn8cAAIKAAYKwwl/DgDIAAAKAAYKwwl/DgDIAAAAAA==.',
Ps='Psyrine:BAAANQAECgUIBQAAAA==.',
Py='Pyrö:BAABNQAECn8bAAIWAAkKxQElAwGJAAAWAAkKxQElAwGJAAAAAA==.',
['Pü']='Püff:BAAANQAECgIIAgAAAA==.',
Qu='Qu:BAABNQAECn88AAIYAAoK7h4MJwCDAgAYAAoK7h4MJwCDAgAAAA==.',
Ra='Rakdoc:BAAANQADCgQIBAAAAA==.Rattlesnake:BAAANQADCggIMAAAAA==.Raymonnd:BAAANQADCgYICwAAAA==.',
Re='Reborn:BAAANQADCgUIBQABNQAECgkJHQAYAKcPAA==.Reflektor:BAAANQABCgQIBAAAAA==.Renägäde:BAAANQAECggIEAAAAA==.Retiredfurry:BAABNQAECn83AAMlAAoK6yIlCAAPAwAlAAoK6yIlCAAPAwACAAgKzR0jFADvAQAAAA==.',
Ri='Ricodadawg:BAABNQAECn9DAAIWAAoKRCNqIABYAwAWAAoKRCNqIABYAwAAAA==.',
Ro='Roosk:BAAANQADCgUIBQAAAA==.Roshak:BAAANQADCgYIDQAAAA==.Rotspawn:BAAANQAECggJCAAAAA==.',
Ru='Runningbearr:BAAANQADCggIEgAAAA==.Runningdemon:BAAANQADCgYICwABNQAECgoKIwANAPgLAA==.Runningshama:BAABNQAECn8jAAMNAAoK+AvPTwBfAQANAAoK+AvPTwBfAQAHAAEK+hJs5QAxAAAAAA==.Rurahk:BAAANQAECgYIDwAAAA==.',
['Rõ']='Rõbb:BAAANQAECgEIAQAAAA==.',
Sa='Sabaak:BAABNQAECn8ZAAIGAAUKAhvE0AB6AQAGAAUKAhvE0AB6AQAAAA==.Sabel:BAAANQADCggIDgAAAA==.Saeriin:BAAANQAECgYIEwAAAA==.Saintsnyder:BAABNQAECn8nAAQIAAkKCguoPgACAQAIAAUKKRaoPgACAQAGAAgKCQUHHAHwAAAQAAEKGgHgPQEPAAAAAA==.Saithis:BAAANQAECgEIAwAAAA==.Sanorasong:BAAANQAECgYIEwAAAA==.Saphaa:BAAANQAECgUIBQAAAA==.Saphirra:BAAANQADCggIEQAAAA==.Sarylin:BAAANQAECgQIBwAAAA==.Satansshadow:BAAANQADCgEIAQAAAA==.Sathona:BAAANQAECggIDAAAAA==.Sathpriest:BAABNQAECn8jAAQSAAoKNSIhDgBTAwASAAkKTyMhDgBTAwAmAAIKyRzxGACoAAAeAAIKZQ6xUAA+AAAAAA==.Sathrel:BAAANQADCgMIAwAAAA==.',
Sc='Schio:BAABNQAECn8aAAIKAAYKHRKjDADXAAAKAAYKHRKjDADXAAAAAA==.',
Se='Severussnape:BAABNQAECn8sAAMJAAgKuQcIuQBbAQAJAAgKrAcIuQBbAQAKAAQKlwNjTQCXAAAAAA==.',
Sh='Shamrorag:BAAANQADCgQICAAAAA==.Sharpeyez:BAAANQAECgQIBAAAAA==.She:BAABNQAECn8rAAIjAAoK2BcWEAB7AgAjAAoK2BcWEAB7AgAAAA==.Shehealz:BAAANQADCggICQAAAA==.Shekxxy:BAAANQAECgIIAwABNQAFFAQIBgACALkUAA==.Shortstack:BAAANQAECgYIDAAAAA==.',
Si='Simpmother:BAAANQAECgUIDgAAAA==.Sinensis:BAAANQAECgUICgAAAA==.',
Sk='Skadoosh:BAAANQADCggIDQABNQAFFAYIGgARADsZAA==.Skarletflame:BAAANQADCgMIAwAAAA==.Skarletrose:BAABNQAECn8aAAIhAAYKzRD5PADzAAAhAAYKzRD5PADzAAAAAA==.Skinalittleb:BAAANQAECgQIBAAAAA==.',
Sl='Slaycie:BAABNQAECn8mAAISAAkKRR2HHADGAgASAAkKRR2HHADGAgAAAA==.',
Sn='Sneek:BAAANQAECgUIDgAAAA==.Snugglebus:BAAANQAECgIIAgAAAA==.',
So='Solaara:BAAANQAECgUIEQAAAA==.',
Sp='Spaghett:BAABNQAECn8hAAMdAAgKxhVDEQDUAQAdAAgKxhVDEQDUAQACAAYK6Qb8VQCUAAAAAA==.',
St='Stanger:BAABNQAECn8ZAAIHAAoKph7oKADAAgAHAAoKph7oKADAAgAAAA==.Starlight:BAABNQAECn8jAAIiAAoKdh3VDgCYAgAiAAoKdh3VDgCYAgABNQAECgoKRAAGALQlAA==.Stonefly:BAAANQAECgEIAQAAAA==.',
Su='Succulent:BAEANQAECgIIAgAAAA==.',
Sy='Syrden:BAABNQAECn8yAAITAAoKMA6gKgDJAQATAAoKMA6gKgDJAQAAAA==.Syren:BAAANQADCgEIAQAAAA==.',
Ta='Tael:BAABNQAECn8vAAIPAAkK5R5KBgAnAgAPAAkK5R5KBgAnAgAAAA==.Tangylizard:BAABNQAECn8hAAMSAAoKBSEVDgBFAwASAAoK6SAVDgBFAwAmAAUKoxSEDwAzAQAAAA==.Tawainai:BAABNQAECn8tAAIWAAgKFhK0ugAOAgAWAAgKFhK0ugAOAgAAAA==.',
Te='Tessla:BAABNQAECn8zAAMNAAoKuxYDMwDTAQANAAoKuxYDMwDTAQAHAAIKtQGtFgE9AAAAAA==.Tetragram:BAABNQAECn9RAAICAAoKTiSkAgBHAwACAAoKTiSkAgBHAwAAAA==.',
Th='Thelarï:BAABNQAECn8sAAIEAAgKCgnoqgCvAQAEAAgKCgnoqgCvAQAAAA==.Thors:BAABNQAECn84AAIGAAkKpiPHEwB3AwAGAAkKpiPHEwB3AwAAAA==.Thundertoes:BAABNQAECn8qAAMHAAgKsBecRwDCAQAHAAgKsBecRwDCAQANAAUKDw0KuAAiAQAAAA==.',
Ti='Tia:BAAANQADCgEIAQAAAA==.Timmy:BAAANQADCgIIAgAAAA==.Tiquandeisha:BAABNQAECn8dAAMhAAYK8RWbZAB+AQAhAAYK8RWbZAB+AQABAAEKTwiIuAAmAAAAAA==.Titåx:BAAANQADCgYIBgAAAA==.',
To='Tonik:BAABNQAECn8bAAMNAAcKiBCXqABDAQANAAYKSQ6XqABDAQAHAAUKmwyV1AC+AAAAAA==.Torgoth:BAABNQAECn8cAAIVAAYKaAloHQAHAQAVAAYKaAloHQAHAQAAAA==.Toshido:BAAANQAECgYIEwAAAA==.Totemtroller:BAAANQAECgUIBAAAAA==.Toy:BAAANQAECgMIAwAAAA==.',
Tr='Trevize:BAAANQAECggIAgAAAA==.',
Tw='Twilightsoul:BAAANQAECggIAQAAAA==.',
Ub='Ubully:BAAANQADCgMIAwAAAA==.',
Ul='Ultane:BAAANQAECgQIDAAAAA==.',
Un='Unholypally:BAAANQADCggIFwAAAA==.',
Va='Valashar:BAAANQADCgcIDQAAAA==.Valiantaine:BAABNQAECn89AAQGAAoKUBzzPgDYAgAGAAoKUBzzPgDYAgAQAAcKOQQTrwAhAQAIAAMKghQEMwC7AAAAAA==.Valiantaint:BAABNQAECn8qAAIRAAoKnhb7FADlAQARAAoKnhb7FADlAQABNQAECgoKPQAGAFAcAA==.Valiantroar:BAAANQAECgYIBgABNQAECgoKPQAGAFAcAA==.Vashon:BAAANQADCgQIBwAAAA==.',
Ve='Velherun:BAABNQAECn8kAAIGAAgKdxUYnADqAQAGAAgKdxUYnADqAQAAAA==.Vendel:BAABNQAECn8wAAINAAoKUyQCBwCxAwANAAoKUyQCBwCxAwAAAA==.Vexxaa:BAABNQAECn8cAAIEAAYKoAwbpAAlAQAEAAYKoAwbpAAlAQAAAA==.',
Vi='Virajr:BAAANQAECgQICQAAAA==.Vissiction:BAABNQAECn8iAAIRAAgKfxVPHwBxAQARAAgKfxVPHwBxAQAAAA==.Vistine:BAABNQAECn8YAAIIAAYKsgjkOgCUAAAIAAYKsgjkOgCUAAABNQAECgoKMwANALsWAA==.Vitez:BAABNQAECn8XAAIJAAgKegiCtgBhAQAJAAgKegiCtgBhAQAAAA==.',
Wa='Waterslide:BAAANQADCgYIEQAAAA==.',
We='Weatherman:BAAANQADCgQIBAAAAA==.Wendy:BAABNQAECn86AAIHAAoK3xsLTwAoAgAHAAoK3xsLTwAoAgAAAA==.',
Wh='Whack:BAAANQADCgIIAgAAAA==.Whemeo:BAAANQAECgEIAQAAAA==.Whitesox:BAAANQADCgQJBAAAAA==.',
Wi='Win:BAABNQAECn8cAAMTAAcKCwkgPQA6AQATAAcKCwkgPQA6AQAiAAcKxAwaPgAAAQABNQAFFAEIAQAFAAAAAA==.Winkster:BAAANQAECgcIDwAAAA==.',
Xa='Xanadu:BAABNQAECn82AAMmAAoKECHgAAA8AwAmAAoKECHgAAA8AwASAAEKUxLD/AAyAAAAAA==.Xarinia:BAAANQAECgIIAgABNQAECgoKPgABAOYMAA==.',
Xb='Xbear:BAABNQAECn8cAAIbAAYK/hSOKABRAQAbAAYK/hSOKABRAQABNQAFFAYIHAAjAAwWAA==.',
Xd='Xdynasty:BAACNQAFFH8cAAMjAAYKDBYpCABXAQAjAAYKDBYpCABXAQAgAAEKpBvKHABSAAA1AAQKf0EAAyMACgoBIvoHAPoCACMACgpHH/oHAPoCACAABAqmHqBXAFwBAAAA.',
Xe='Xendier:BAAANQADCgIIAgAAAA==.',
Xi='Xióngchäo:BAAANQADCgYIEgABNQAECgYIDQAFAAAAAA==.',
Xo='Xo:BAAANQADCggICAABNQAFFAEIAQAFAAAAAA==.',
Za='Zabazz:BAABNQAECn8yAAMHAAkKPBGaOQABAgAHAAkKPBGaOQABAgANAAQKrQZfvgBgAAAAAA==.Zabenir:BAABNQAECn8XAAIeAAYKWxXKIQA8AQAeAAYKWxXKIQA8AQAAAA==.Zalrote:BAAANQADCggICgABNQAECgoKPgABAOYMAA==.Zaraina:BAABNQAECn8bAAISAAYKyRbzaQBjAQASAAYKyRbzaQBjAQABNQAFFAYIGgARADsZAA==.',
Ze='Zerototem:BAABNQAECn8rAAMHAAgKyBeTTQAtAgAHAAgKyBeTTQAtAgANAAIKGAlsEQFpAAAAAA==.',
Zo='Zorusii:BAAANQADCgcIDQABNQAFFAYIGgARADsZAA==.',
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
