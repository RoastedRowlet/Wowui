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

local lookup = {'Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Hunter-Survival','Shaman-Elemental','Mage-Frost','Shaman-Restoration','DeathKnight-Blood','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Adabisi:BAAALgADCgEJAQAAAA==.Addu:BAAALgAECgUJBQAAAA==.Adiforis:BAAALgAECgUJCQAAAA==.Adobo:BAAALgAECgkJCgAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIBAAgJpQkjEQAlAQABAAgJpQkjEQAlAQAAAA==.Aerandir:BAABLgAECn8UAAMCAAYJNQrjrwD5AAACAAYJNQrjrwD5AAADAAEJAAAXeQAqAAABLgAECgcJFAAEAGMNAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgcJEwAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn8mAAIFAAgJ1w5kDgBGAQAFAAgJ1w5kDgBGAQAAAA==.Alyestra:BAAALgAECgYJEgAAAA==.',
Am='Ambien:BAAALgAECgEJAQAAAA==.',
An='Anibundance:BAAALgAECgcJDAABLgAECgkJLQAGAJ0iAA==.Animyst:BAACLgAFFH8FAAIHAAMJ+R26HwD8AAAHAAMJ+R26HwD8AAAuAAQKfz0AAgcACAkjJZAEAEADAAcACAkjJZAEAEADAAEuAAQKCQktAAYAnSIA.Anipaltu:BAACLgAFFH8HAAIIAAQJHQs+HwD8AAAIAAQJHQs+HwD8AAAuAAQKfxoAAggABgmVH+IcAPgBAAgABgmVH+IcAPgBAAEuAAQKCQktAAYAnSIA.Aniron:BAAALgAECgYJDwABLgAECgkJLQAGAJ0iAA==.Anirot:BAABLgAECn8tAAIGAAkJnSIhAwBKAwAGAAkJnSIhAwBKAwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAGAJ0iAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMJAAYJmQ4sWQAOAQAJAAYJmQ4sWQAOAQAKAAYJ9AnyRADKAAAAAA==.Arcanium:BAAALgAECgEJAQAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8oAAILAAkJZiHeDADFAgALAAkJZiHeDADFAgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJCwAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Banashain:BAAALgADCgEJAgAAAA==.Bartholomew:BAABLgAECn8lAAIHAAkJphwJCQDaAgAHAAkJphwJCQDaAgAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn8uAAIGAAgJayUHAwBNAwAGAAgJayUHAwBNAwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgUJBgAAAA==.',
Bo='Boffadeez:BAAALgAECgQJBQAAAA==.Boombawks:BAAALgADCgUJBQABLgAECgEJAQAMAAAAAA==.Boryndin:BAABLgAECn8hAAINAAgJ8hk3DgDeAQANAAgJ8hk3DgDeAQAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAACLgAFFH8HAAIOAAQJngdaPQASAQAOAAQJngdaPQASAQAuAAQKfzQAAg4ACQl9Fyw6ADoCAA4ACQl9Fyw6ADoCAAAA.',
Bu='Bulgrim:BAAALgADCgEJAQAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgEJAQAAAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgYJDAAAAA==.Cherypoptart:BAABLgAECn8XAAIPAAcJLSITEAA4AgAPAAcJLSITEAA4AgAAAA==.Chrismeister:BAAALgAECgUJCwAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.Clothpally:BAAALgAECgkJCQAAAA==.',
Co='Codah:BAAALgAECgIJBgAAAA==.Coomonka:BAAALgADCgcJCQAAAA==.Corbenik:BAAALgAECgIJBgABLgAECgcJGAACAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crethasmus:BAAALgAECgIJAgAAAA==.Crettephal:BAEALgAECgQJCgAAAA==.Crodo:BAAALgADCgYJBgAAAA==.',
['Cä']='Cähira:BAAALgADCgUJBQABLgADCgYJCQAMAAAAAA==.',
Da='Daellan:BAAALgAECgUJCQAAAA==.Dainaira:BAAALgAECgcJDAAAAA==.Daisia:BAABLgAECn8ZAAIQAAgJYQZbJwBEAQAQAAgJYQZbJwBEAQAAAA==.Dalarrong:BAAALgAECgIJAgAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgAECgEJAQAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8XAAMCAAgJMg+zcwA/AQACAAcJ4w2zcwA/AQADAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8mAAINAAgJQRgpDgDfAQANAAgJQRgpDgDfAQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAECggJEAAMAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8bAAIRAAgJHA6HNQA4AQARAAgJHA6HNQA4AQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgUJCgAAAA==.Draqula:BAAALgADCggJDQAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8jAAISAAcJ/AxIigBJAQASAAcJ/AxIigBJAQAAAA==.',
Du='Dura:BAABLgAECn8pAAITAAgJxRWzJwD2AQATAAgJxRWzJwD2AQAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn80AAIDAAgJZAu2DwAbAQADAAgJZAu2DwAbAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn9BAAMEAAkJCA3USwC/AQAEAAkJCA3USwC/AQAUAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgEJAwABLgAECgUJCgAMAAAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgAMAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8tAAQPAAgJtAzrJwBoAQAPAAgJtAzrJwBoAQAVAAYJ2wnjLwAhAQAGAAUJYApfSwCLAAAAAA==.Faith:BAABLgAECn8bAAIOAAYJlxwZYQCRAQAOAAYJlxwZYQCRAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgADCgkJEAABLgAECgkJKwAOACwbAA==.Firebug:BAABLgAECn8ZAAINAAcJ5AX6JwDNAAANAAcJ5AX6JwDNAAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgQJBwAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAQJEwAWAHEhAA==.',
Fu='Furnok:BAABLgAECn8uAAMRAAgJfRI3JQCVAQARAAgJfRI3JQCVAQATAAQJMhCDgQCiAAAAAA==.Fuzzyshukk:BAAALgAECgQJCAAAAA==.',
Ga='Galethia:BAAALgADCgkJHgAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAQJBwAXAJ8IAA==.',
Gh='Ghutz:BAACLgAFFH8LAAIYAAMJ8g1BGwDKAAAYAAMJ8g1BGwDKAAAuAAQKfzgAAxgACAlBGdYOANYBABgACAlBGdYOANYBABkABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAABLgAECn8WAAIIAAgJ6BoJHgDuAQAIAAgJ6BoJHgDuAQAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.Gonja:BAAALgADCgYJCAAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn80AAIXAAgJSxTmDQDPAQAXAAgJSxTmDQDPAQAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8YAAIOAAgJihFdYwCMAQAOAAgJihFdYwCMAQAAAA==.',
Ho='Hollet:BAABLgAECn8bAAIaAAYJGhAOcwAuAQAaAAYJGhAOcwAuAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8MAAIIAAQJGx3dEwBZAQAIAAQJGx3dEwBZAQAuAAQKfyUAAwgACQmRIqEFABIDAAgACQmRIqEFABIDAA4AAQlCB4VzAS0AAAAA.',
Hu='Huckk:BAAALgADCgUJBQAAAA==.',
Hy='Hylen:BAAALgAECggJEQAAAA==.',
Ib='Ibrandul:BAABLgAECn8pAAIOAAgJHBKTYACSAQAOAAgJHBKTYACSAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAISAAcJ8wHa7ACkAAASAAcJ8wHa7ACkAAAAAA==.',
Ir='Ironhuntress:BAABLgAECn8ZAAIaAAgJvg/fSwCTAQAaAAgJvg/fSwCTAQAAAA==.',
It='Ithro:BAABLgAECn8nAAIbAAkJJxhpBAAoAgAbAAkJJxhpBAAoAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJDwAAAA==.',
Ja='Jarlo:BAABLgAECn80AAIbAAgJ2Rg1BQAMAgAbAAgJ2Rg1BQAMAgAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQAOAMUaAA==.Jefficiently:BAAALgAECgUJBQABLgAECgkJLQAOAMUaAA==.Jefriel:BAAALgAECgYJBgABLgAECgkJLQAOAMUaAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8nAAIYAAkJ1CHKAwDGAgAYAAkJ1CHKAwDGAgAAAA==.',
Ju='Juanhunglow:BAAALgADCgkJNAAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8nAAMEAAgJKiFeHgByAgAEAAgJKiFeHgByAgAUAAEJ/w8hUQApAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn8zAAIaAAcJUxSRXQBhAQAaAAcJUxSRXQBhAQAAAA==.Karyia:BAAALgAECgUJBQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Keruptadin:BAAALgAECgQJBAAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8rAAIXAAkJ/BoIBQCwAgAXAAkJ/BoIBQCwAgAAAA==.',
Kr='Kreltor:BAABLgAECn8nAAITAAgJRiLDCQDxAgATAAgJRiLDCQDxAgAAAA==.Kryptikz:BAAALgAECggJDgAAAA==.Krystoferson:BAABLgAECn8ZAAIcAAgJOwK/MADtAAAcAAgJOwK/MADtAAAAAA==.',
La='Largar:BAAALgADCgQJBAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgABLgAECgEJAQAMAAAAAA==.Leianii:BAAALgAECgEJAQAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAICAAcJ8QesgwBTAQACAAcJ8QesgwBTAQAAAA==.Lillat:BAAALgAECgYJEQAAAA==.Lin:BAAALgAECgEJAQAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgADCgkJCwAAAA==.Luuggork:BAAALgADCgYJBgAAAA==.',
Ly='Lyarith:BAAALgADCgUJBQAAAA==.Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJAgAAAA==.',
['Lì']='Lìesson:BAABLgAECn8mAAIOAAkJfiHEDADmAgAOAAkJfiHEDADmAgAAAA==.',
Ma='Mabo:BAAALgAECgEJAQAAAA==.Mackaroni:BAACLgAFFH8GAAISAAQJWhDZTQAwAQASAAQJWhDZTQAwAQAuAAQKfxoAAhIACAlSFolTAMcBABIACAlSFolTAMcBAAEuAAQKCAkQAAwAAAAA.Madolynne:BAAALgADCgIJAgAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn8zAAISAAgJBBfyRwDqAQASAAgJBBfyRwDqAQAAAA==.Magimiester:BAAALgADCgEJAQABLgAECgUJCwAMAAAAAA==.Makkagg:BAACLgAFFH8RAAMNAAQJZBTpDgAVAQANAAQJZBTpDgAVAQAZAAIJRAcfQQBFAAAuAAQKfzUAAw0ACQkiIWgDAOMCAA0ACQkiIWgDAOMCABkACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8aAAISAAgJlwXonQAmAQASAAgJlwXonQAmAQAAAA==.',
Mi='Milagrosa:BAABLgAECn8jAAIWAAkJJQ3wJgCLAQAWAAkJJQ3wJgCLAQAAAA==.Mirael:BAACLgAFFH8KAAIaAAQJqxyDIwBBAQAaAAQJqxyDIwBBAQAuAAQKfy0AAhoACQnkH8AIAAcDABoACQnkH8AIAAcDAAAA.Mishuntsalot:BAAALgADCgYJCQAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAAALgAECgYJEwAAAA==.',
Mu='Mumsms:BAAALgAECgkJBgAAAA==.Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8YAAIJAAcJdAwEUwAjAQAJAAcJdAwEUwAjAQAAAA==.Mystryx:BAAALgAECggJEQAAAA==.',
['Mà']='Màck:BAAALgAECggJEAAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8kAAICAAYJ2xeaYgBnAQACAAYJ2xeaYgBnAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQAOAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAACAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8XAAIOAAcJWAcgwQDlAAAOAAcJWAcgwQDlAAAAAA==.',
Oa='Oathmere:BAAALgADCgUJBQAAAA==.',
Og='Ogrusao:BAABLgAECn8ZAAIaAAgJ/QsiUwB9AQAaAAgJ/QsiUwB9AQAAAA==.Ogun:BAAALgADCgEJAQAAAA==.',
Pa='Panasaurus:BAABLgAECn80AAIdAAgJ+RS7CQCiAQAdAAgJ+RS7CQCiAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIeAAcJwBmCMgCHAQAeAAcJwBmCMgCHAQAAAA==.Pelli:BAABLgAECn8nAAIPAAgJzAYoMwAnAQAPAAgJzAYoMwAnAQAAAA==.Pendraig:BAAALgADCgUJCAAAAA==.Pestilense:BAAALgADCgIJAgAAAA==.',
Pl='Plaza:BAAALgAECgkJCgAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJDgAMAAAAAA==.Rayst:BAABLgAECn8aAAISAAYJVQIV7QCjAAASAAYJVQIV7QCjAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAABLgAECn8UAAIJAAcJrSKvDwC4AgAJAAcJrSKvDwC4AgABLgAFFAMJCQAJADEUAA==.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8ZAAIZAAgJIiG3DQBxAgAZAAgJIiG3DQBxAgAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn8nAAMQAAgJJBTwFwDEAQAQAAgJsRPwFwDEAQAaAAEJ+hSM7QA/AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAfAGUZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Sagearian:BAAALgAECgMJBAAAAA==.Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8YAAMaAAYJawiYlgDiAAAaAAYJXgiYlgDiAAAQAAQJfAJlSQBgAAAAAA==.Samanda:BAABLgAECn8YAAIgAAYJSg4ZGwD9AAAgAAYJSg4ZGwD9AAAAAA==.Samshir:BAABLgAECn8UAAIEAAcJYw0MgABBAQAEAAcJYw0MgABBAQAAAA==.',
Sc='Scorned:BAABLgAECn8iAAILAAcJ4hCvcAAdAQALAAcJ4hCvcAAdAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAAALgAECgcJCwAAAA==.',
Sh='Shadowmane:BAAALgAECgEJAQAAAA==.Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgMJAwAAAA==.Shaylinn:BAAALgADCgkJMAAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAFFAQJDAAIABsdAA==.',
Si='Siella:BAABLgAECn8pAAIGAAgJMRMwHQC5AQAGAAgJMRMwHQC5AQAAAA==.Sileves:BAAALgAECgEJAgABLgAECgUJCgAMAAAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8lAAISAAgJjCAZHwCKAgASAAgJjCAZHwCKAgAAAA==.',
So='Solar:BAAALgAECgEJAQAAAA==.Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgADCgIJAgABLgAECgEJAQAMAAAAAA==.Soulbaine:BAAALgAECgYJDwAAAA==.',
Sp='Spazeric:BAABLgAECn8eAAMHAAgJcxV+HgDoAQAHAAgJcxV+HgDoAQAhAAYJORfmNwD5AAAAAA==.Spheria:BAABLgAECn8vAAICAAgJsQdodQA7AQACAAgJsQdodQA7AQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashara:BAAALgADCgEJAQAAAA==.Talashea:BAAALgAECgEJAgAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECgYJCAAMAAAAAA==.Tarall:BAAALgAECgEJAQAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8aAAIiAAYJmwZBFwDTAAAiAAYJmwZBFwDTAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgADCgkJJgAAAA==.',
Ti='Tim:BAABLgAFFH8FAAITAAMJ0Ra4NgDXAAATAAMJ0Ra4NgDXAAAAAA==.Timeshadow:BAABLgAECn8XAAIcAAYJRwIfPACfAAAcAAYJRwIfPACfAAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8oAAISAAkJixcwNwAhAgASAAkJixcwNwAhAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAABLgAECn8WAAIOAAcJRxFffABXAQAOAAcJRxFffABXAQAAAA==.',
Tr='Triplesix:BAAALgAECggJEwAAAA==.Trittia:BAABLgAECn8fAAIZAAcJdgu4OgA4AQAZAAcJdgu4OgA4AQAAAA==.',
Tu='Tukk:BAAALgAECgYJEwAAAA==.Turtle:BAAALgAECgEJBQAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIJAAgJCBWOKQDoAQAJAAgJCBWOKQDoAQABLgAECgcJEQAMAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgADCgUJBQABLgAECgQJBAAMAAAAAA==.',
Ur='Urza:BAAALgAECgUJBwAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn81AAMaAAkJVR14DwCvAgAaAAkJVR14DwCvAgABAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgQJBAAAAA==.Vexxa:BAABLgAECn8YAAILAAkJPBjHPwCrAQALAAkJPBjHPwCrAQAAAA==.',
Vi='Viridania:BAAALgAECgEJAQAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgABCgMJBAAMAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAABLgAECggJDgAMAAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn8uAAIPAAgJxRs9DwBDAgAPAAgJxRs9DwBDAgAAAA==.Wiggleston:BAABLgAECn8WAAMIAAgJtQqINABaAQAIAAgJtQqINABaAQAOAAMJXwMAAAAAAAAAAA==.Willscarlet:BAAALgAECgYJDAAAAA==.',
Wy='Wylethia:BAAALgADCgcJCAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAECgcJFAAEAGMNAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgADCgkJGAAAAA==.',
Za='Zarathia:BAAALgAECgYJDwAAAA==.Zaritym:BAABLgAECn8ZAAMHAAgJWxg1GQAUAgAHAAgJWxg1GQAUAgAhAAQJbw/yVgCIAAAAAA==.Zarrilin:BAABLgAECn8oAAISAAkJlBe1NgAiAgASAAkJlBe1NgAiAgAAAA==.',
Ze='Zebop:BAAALgADCgkJDQAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8MAAIDAAQJ3g2bBAAoAQADAAQJ3g2bBAAoAQAuAAQKf0UAAgMACQnNHA8CAIcCAAMACQnNHA8CAIcCAAAA.',
Zo='Zoeheals:BAAALgAECgYJCAAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCQAAAA==.Zulmahn:BAABLgAECn8fAAMTAAcJcBBZSgBWAQATAAcJcBBZSgBWAQARAAYJJATCWwCkAAAAAA==.',
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
