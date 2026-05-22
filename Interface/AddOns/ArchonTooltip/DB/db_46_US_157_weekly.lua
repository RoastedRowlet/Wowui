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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','Hunter-BeastMastery','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Shaman-Elemental','Rogue-Assassination','Mage-Arcane','Monk-Brewmaster','Monk-Windwalker','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaralia:BAABLgAECn8fAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAIJBgyGRgBsAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgADCgYJBwAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECggJDwADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgcJKQAEAHAVAA==.Alearia:BAAALgADCgEJAQAAAA==.Alewynt:BAAALgAECgEJBQAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgADCgcJDwAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgYJCwAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgADCgcJFAAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgQJBAAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJAwAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJCwAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAWSOgC3AAACAAYJxAWSOgC3AAAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJBgAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAUJCwAGAAkTAA==.',
Be='Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8UAAIHAAcJtQE0PQCwAAAHAAcJtQE0PQCwAAAAAA==.Bloodedge:BAABLgAECn8dAAIIAAkJiBpGBwBtAgAIAAkJiBpGBwBtAgAAAA==.',
Bo='Bobbyswagger:BAAALgAFFAIJBAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn8aAAIJAAYJUyNwDwBEAgAJAAYJUyNwDwBEAgAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.',
Bu='Bungeholio:BAACLgAFFH8GAAIBAAIJMAPSIQB7AAABAAIJMAPSIQB7AAAuAAQKfx8AAgEACAmgDgsuABUBAAEACAmgDgsuABUBAAAA.Bunzzlle:BAAALgAECgEJAQABLgAFFAIJBgABADADAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAUJCwAGAAkTAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Cannelle:BAABLgAECn8aAAIEAAkJEwbpZgBvAQAEAAkJEwbpZgBvAQAAAA==.Carden:BAABLgAECn8hAAMGAAcJMCGMCgATAgAGAAcJMCGMCgATAgAKAAEJzwpzHwE3AAAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8dAAILAAgJxCR1CwAmAwALAAgJxCR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAABLgAECn8YAAIKAAgJeQSfkQD5AAAKAAgJeQSfkQD5AAAAAA==.Chillywillie:BAABLgAECn8bAAIMAAgJpw6IJgB1AQAMAAgJpw6IJgB1AQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgADCgcJBwAAAA==.Chrodne:BAAALgAECgMJBwAAAA==.Chromax:BAAALgADCgYJCQAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Cleptodog:BAAALgAECgkJAwAAAA==.Clintbarton:BAAALgAECgYJDgAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgUJBwAAAA==.',
Ct='Cthullu:BAACLgAFFH8LAAIGAAUJCRMJGwCiAAAGAAUJCRMJGwCiAAAuAAQKfxkAAwYACQkuHb4GAG8CAAYACQlfHL4GAG8CAAoABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8bAAIKAAgJPxoLRgCpAQAKAAgJPxoLRgCpAQAAAA==.',
Da='Dabi:BAAALgAECgQJEAAAAA==.Daemon:BAAALgAECgcJEgAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAABLgAECn84AAQNAAkJfB1bDgCmAgANAAkJfB1bDgCmAgAOAAQJXxLYKAAfAQAPAAEJshkQJAA7AAAAAA==.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Dayday:BAAALgAECgIJAgABLgAECggJFwAQAHgTAA==.',
De='Deathsend:BAABLgAECn8eAAIKAAcJ1QRplgDwAAAKAAcJ1QRplgDwAAAAAA==.Decamoose:BAABLgAECn8WAAIRAAgJohCnCgByAQARAAgJohCnCgByAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8FAAISAAIJcgyhCQCSAAASAAIJcgyhCQCSAAAAAA==.Deepstate:BAAALgAECgIJAgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJCwAJAI8XAA==.Demonaholio:BAAALgAECgEJAQABLgAFFAIJBgABADADAA==.Demonicade:BAABLgAECn8eAAMNAAgJQQthYwA6AQANAAcJQQthYwA6AQAOAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.',
Di='Dima:BAABLgAECn8wAAITAAgJOyBVEwBuAgATAAgJOyBVEwBuAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgQJBwAAAA==.',
Dn='Dne:BAABLgAECn8kAAIKAAgJxQ98YgDMAQAKAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAABLgAECn8zAAMFAAkJuyBuBgDnAgAFAAkJuyBuBgDnAgAUAAgJBx4EBQBdAgAAAA==.Dornnbryda:BAAALgAECggJEAAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn8oAAQVAAgJYB/CBADcAQAWAAgJ9xuFEwD2AQAVAAYJhyLCBADcAQAXAAYJuAXNGgDkAAAAAA==.Drecarus:BAAALgAECggJEwAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAUJCwAGAAkTAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Ec='Echidna:BAAALgADCggJDQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgcJGQAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgQJBgADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8aAAMMAAgJSRVbJACDAQAMAAgJSRVbJACDAQAYAAEJYwKdXAAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJBgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAAALgAECgYJEgAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDQAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgADCgcJDAAAAA==.Feltank:BAAALgAECgQJBAABLgAFFAUJCwAGAAkTAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8XAAIBAAgJZQ/UIABqAQABAAgJZQ/UIABqAQAAAA==.',
Ga='Gailinn:BAAALgAECgQJBgAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAABLgAECn8aAAQNAAgJox8XGgBMAgANAAgJox8XGgBMAgAOAAIJChIsVAByAAAPAAEJHRkmKQBNAAAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8fAAIZAAgJORrdHgD/AQAZAAgJORrdHgD/AQAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJCwAJAI8XAA==.Grimmlockk:BAAALgAECgUJCgABLgAFFAcJFgALAGYcAA==.Grimroc:BAAALgADCgQJBAAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIaAAgJPA/1FABTAQAaAAgJPA/1FABTAQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCgcJBwABLgADCgkJGAADAAAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hassad:BAAALgADCgcJDQAAAA==.',
He='Healaton:BAAALgAECggJDwAAAA==.Healmonger:BAACLgAFFH8FAAIHAAMJwwdGFwCxAAAHAAMJwwdGFwCxAAAuAAQKfykAAwcACQnmFL0OADECAAcACQnmFL0OADECAAEABglsBw04AN8AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAABLgAFFH8FAAMKAAMJMwqwcADPAAAKAAMJMwqwcADPAAAbAAEJEQIOEwA6AAAAAA==.',
Hi='Hilgasmic:BAAALgAECgcJCgAAAA==.',
Ho='Hohenhaim:BAAALgAECgkJEQAAAA==.Holly:BAAALgAECgcJDAAAAA==.Holykal:BAEBLgAECn8gAAIQAAgJDB7OIAA/AgAQAAgJDB7OIAA/AgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH8kAAIHAAYJCgOCCABiAQAHAAYJCgOCCABiAQAuAAQKfz0AAgcACQneF+4MAEwCAAcACQneF+4MAEwCAAAA.',
Ib='Ibelurkin:BAAALgADCgMJAwAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgEJAgADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgMJCAAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8fAAIcAAgJ5Rt2CgAyAgAcAAgJ5Rt2CgAyAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8bAAILAAYJVSPnBwD3AQALAAYJVSPnBwD3AQAuAAQKfzoAAwsACQmUJVYCAEUDAAsACQmUJVYCAEUDAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgEJAQAAAA==.Kaho:BAAALgAECgQJBwAAAA==.Karkas:BAAALgAECgYJCgAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMKAAkJKgp+ZABUAQAKAAgJ6gl+ZABUAQAbAAMJUgtHFwCPAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJJQAaAMMWAA==.Kayroonrangi:BAAALgAECgEJAgAAAA==.',
Ke='Kearyn:BAABLgAECn8lAAMaAAkJwxbDCgD2AQAaAAkJwxbDCgD2AQAMAAQJIgr1TAC/AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgADCgkJEQABLgAECggJLwALAOQjAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8pAAIEAAcJcBUWYQB9AQAEAAcJcBUWYQB9AQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn8uAAIEAAkJxCGuDADjAgAEAAkJxCGuDADjAgAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCggJCAAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.Lazuleon:BAAALgAECgcJBwAAAA==.',
Le='Leap:BAACLgAFFH8GAAIdAAMJnAWTBgCOAAAdAAMJnAWTBgCOAAAuAAQKfx0AAh0ACQl/FPAFAOcBAB0ACQl/FPAFAOcBAAAA.Leonîdas:BAAALgAECgEJAQAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgUJBQAAAA==.Lionroar:BAACLgAFFH8YAAIeAAUJZRiNDwCHAQAeAAUJZRiNDwCHAQAuAAQKfy0AAx4ACAlhIXkSAKICAB4ACAlhIXkSAKICAB8ABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAAALgAECgkJBgAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAECgkJJAASAIEYAA==.Lorellei:BAABLgAECn8XAAIHAAYJ7A+nLAAcAQAHAAYJ7A+nLAAcAQAAAA==.Lothgow:BAAALgAECgUJCAAAAA==.Lourdes:BAABLgAECn8WAAIEAAgJhgJ8qwDtAAAEAAgJhgJ8qwDtAAAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAUJCwAGAAkTAA==.',
Ma='Magchro:BAAALgADCgEJAQAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJCAAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn8oAAIQAAgJtyK4DgC3AgAQAAgJtyK4DgC3AgAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHodAA==.Mewzi:BAAALgAECgQJCQAAAA==.',
Mi='Miah:BAABLgAECn8iAAIRAAYJtRn4CwBYAQARAAYJtRn4CwBYAQAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAECgIJCAADAAAAAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAABLgAECn80AAMNAAgJjR+KJAAPAgANAAYJvyCKJAAPAgAOAAIJXBh/QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgQJBwAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCgcJBwAAAA==.',
Mu='Muffinn:BAABLgAECn8cAAITAAkJBAkwTwBaAQATAAkJBAkwTwBaAQAAAA==.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECggJEQAAAA==.Mymdos:BAAALgAECgcJBwABLgABCgMJAwADAAAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAAALgAECggJEAAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8LAAIMAAMJkBr5HwDmAAAMAAMJkBr5HwDmAAAuAAQKfyIAAgwACQk5IRYHAK8CAAwACQk5IRYHAK8CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8UAAQHAAcJ6xQFJgBMAQAHAAcJ6xQFJgBMAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8YAAIgAAYJXA9MOAD8AAAgAAYJXA9MOAD8AAAAAA==.Nitraina:BAAALgAECgQJBAAAAA==.Niyabelle:BAABLgAECn8eAAMhAAcJ1BrLCQBZAQAcAAcJJBerGgBnAQAhAAYJ9RfLCQBZAQAAAA==.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAAALgAECgcJDwAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECggJDAADAAAAAA==.Okinawa:BAAALgAECgEJAQAAAA==.',
Ol='Oleevia:BAABLgAECn8iAAIBAAkJlBbpDwAOAgABAAkJlBbpDwAOAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJCwAJAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8hAAILAAYJwherEQCVAQALAAYJwherEQCVAQAuAAQKfzQAAgsACQkrIRQLALcCAAsACQkrIRQLALcCAAAA.Orgdynamite:BAAALgAECgUJCAAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgQJBwAAAA==.Paladareian:BAABLgAECn8uAAMFAAkJzh8BBAAjAwAFAAkJzh8BBAAjAwAQAAEJJQUUSwEpAAAAAA==.Pandalin:BAAALgAECgYJDwABLgAECggJDAADAAAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAYJGwALAFUjAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECgcJDAAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJBgAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8XAAQYAAcJrxo9EwBwAQAYAAYJdBs9EwBwAQAaAAcJERcDEwBsAQAMAAEJgg4UegAyAAABLgAFFAMJCAAEAPITAA==.',
Pr='Priestitoot:BAAALgAECgUJCwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.',
Qu='Quadzilla:BAAALgADCgkJDwAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8eAAIQAAYJJAsLlQD+AAAQAAYJJAsLlQD+AAAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgcJDQAAAA==.Retropâlly:BAAALgADCgMJAwAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgQJBwAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJCwAJAI8XAA==.Rockbìter:BAABLgAFFH8LAAIJAAQJjxcPEwA5AQAJAAQJjxcPEwA5AQAAAA==.Rockthyr:BAAALgAECgQJBQABLgAFFAQJCwAJAI8XAA==.Rojas:BAAALgAECgcJDwAAAA==.',
['Ré']='Réåper:BAABLgAECn8aAAIQAAgJuxDkXQBsAQAQAAgJuxDkXQBsAQAAAA==.',
['Rö']='Römana:BAABLgAECn8bAAITAAYJgBJRYgAkAQATAAYJgBJRYgAkAQAAAA==.',
Sa='Saaran:BAAALgAECggJDAAAAA==.Sandoriel:BAAALgADCgkJFQAAAA==.Sapmedaddy:BAAALgAECgEJAgAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAMJCgAKAC8VAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJCgAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn8wAAIEAAgJfiGuEwCtAgAEAAgJfiGuEwCtAgAAAA==.',
Sh='Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAAALgAECgUJDgAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAFFAIJBgABADADAA==.Shatterfrost:BAABLgAECn8oAAMiAAYJ+RqGCgA1AQAEAAYJABkGagBoAQAiAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAECgcJCQADAAAAAA==.Shirraz:BAAALgADCgkJEQAAAA==.',
Si='Sicksdeep:BAACLgAFFH8JAAMYAAMJPgitFQC1AAAYAAMJxAetFQC1AAAMAAIJXgUeOABEAAAuAAQKfx0AAxgACAncFvgJAAoCABgACAncFvgJAAoCAAwABQltCZ1sAAQBAAAA.Silverpaws:BAAALgADCgQJBAAAAA==.Silverstorm:BAAALgAECgYJEAAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgIJAgAAAA==.Skewpin:BAAALgADCgQJBAAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn8uAAIRAAkJ9yFOAQDtAgARAAkJ9yFOAQDtAgAAAA==.',
Sl='Slamma:BAACLgAFFH8gAAIMAAYJcSUPAQAYAgAMAAYJcSUPAQAYAgAuAAQKfz0AAwwACQnCJjUAAPgDAAwACQnCJjUAAPgDABgAAQmVItdAAFkAAAAA.Slammahd:BAAALgAECgkJCQABLgAFFAYJIAAMAHElAA==.Slicedbread:BAACLgAFFH8QAAIJAAYJ5BHiCwCdAQAJAAYJ5BHiCwCdAQAuAAQKfyQABAkACQnqHNQLAHcCAAkACAl7HdQLAHcCACMABgkNIcweAHIBACQAAQniF+JlAEIAAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgIJAgAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgUJBgAAAA==.Sols:BAACLgAFFH8IAAIEAAMJ8hM8VAD8AAAEAAMJ8hM8VAD8AAAuAAQKfyYAAgQACQmjHicMAOgCAAQACQmjHicMAOgCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgADCgQJBgAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgQJBgAAAA==.Speoghii:BAAALgAECgYJEgAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAAALgAECgcJEQAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAAALgAECgYJEAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMQpjJgBCAQABAAgJMQpjJgBCAQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgQJBwAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAMJCwAMAJAaAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAABLgAECn8XAAIQAAYJeBPNeQAvAQAQAAYJeBPNeQAvAQAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgYJBQAAAA==.Taurriel:BAABLgAECn8lAAITAAgJEB7wHAAqAgATAAgJEB7wHAAqAgAAAA==.Tazzm:BAAALgAECgYJBgAAAA==.',
Te='Teranok:BAABLgAECn8gAAIkAAkJsSDLBADPAgAkAAkJsSDLBADPAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8vAAMSAAkJ6CR6AABDAwASAAkJ6CR6AABDAwAZAAEJMgKIrAAdAAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Them:BAAALgAECggJEwAAAA==.Thoir:BAACLgAFFH8kAAIZAAYJLyEjAQD/AQAZAAYJLyEjAQD/AQAuAAQKfz4AAhkACQl3JPwAAJgDABkACQl3JPwAAJgDAAEuAAUUBgkkAAcACgMA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgADCgEJAQAAAA==.Tickells:BAABLgAECn8yAAMCAAkJcwmUGQCrAQACAAkJcwmUGQCrAQABAAkJIw0vGgCgAQAAAA==.Tipsylorcet:BAABLgAECn8nAAIjAAgJuxsCDwAMAgAjAAgJuxsCDwAMAgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgQJBAAAAA==.',
Tr='Tricktìckler:BAAALgAECgQJBwAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgADCgIJAgABLgADCggJFAADAAAAAA==.Turiell:BAAALgAECgMJBAAAAA==.',
Ty='Tybird:BAABLgAECn8dAAIbAAgJryHqBAD7AQAbAAgJryHqBAD7AQAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAYJJAABALkhAA==.Ulyssi:BAACLgAFFH8kAAIBAAYJuSFNAwDjAQABAAYJuSFNAwDjAQAuAAQKfz0AAgEACQmYJYoBAEYDAAEACQmYJYoBAEYDAAAA.',
['Uñ']='Uñàble:BAAALgADCgcJAwAAAA==.',
Va='Valethara:BAAALgADCgIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgYJCQAAAA==.Ven:BAABLgAECn8nAAIBAAgJVAjsKAAyAQABAAgJVAjsKAAyAQAAAA==.Venturecap:BAAALgAECgIJCAAAAA==.Verxina:BAABLgAECn8ZAAIlAAgJFBsOEwDIAQAlAAgJFBsOEwDIAQAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgAECgUJBwAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJDQADAAAAAA==.Voroq:BAAALgAECgEJAwAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAIRAAgJfhYUCwBpAQARAAgJfhYUCwBpAQAAAA==.',
Wa='Warvein:BAAALgAECgEJAQAAAA==.',
We='Weehunt:BAABLgAECn8bAAITAAgJXhq5KADrAQATAAgJXhq5KADrAQAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn8uAAIZAAgJtyTbBAAhAwAZAAgJtyTbBAAhAwAAAA==.Widowfang:BAAALgAECgUJCgAAAA==.Wikka:BAAALgAECgYJDgAAAA==.Wildriver:BAABLgAECn8kAAIeAAgJ+R0XDQCzAgAeAAgJ+R0XDQCzAgAAAA==.',
Xa='Xaehyun:BAACLgAFFH8kAAMkAAYJjCOWAgCtAQAkAAQJiySWAgCtAQAJAAIJyiR2HQDMAAAuAAQKf0EAAyQACQnPJhAAAAoEACQACQnPJhAAAAoEAAkABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQdAAYJiiB4BwC0AQAdAAUJiiB4BwC0AQAIAAUJhB0sKgBzAQALAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8xAAMgAAgJoAx8KgBFAQAgAAgJoAx8KgBFAQAZAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8kAAIGAAYJsx2nBQCeAQAGAAYJsx2nBQCeAQAuAAQKfz0AAgYACQn9IuwCADYDAAYACQn9IuwCADYDAAAA.Xmrpmonk:BAAALgAECgcJEgABLgAFFAYJJAAGALMdAA==.',
Xo='Xohan:BAABLgAECn8qAAIMAAkJBCCJBwCmAgAMAAkJBCCJBwCmAgAAAA==.',
Xy='Xyr:BAAALgADCgEJAQAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8eAAITAAkJ0hR+HQAnAgATAAkJ0hR+HQAnAgAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAQAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8kAAIXAAYJ7B6HAwAqAgAXAAYJ7B6HAwAqAgAuAAQKfz4AAxcACQkII5EBAEgDABcACQkII5EBAEgDABUABQkeHSQNAPYAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAMJCwAMAJAaAA==.Zanne:BAACLgAFFH8QAAIRAAQJ8RgEDwD3AAARAAQJ8RgEDwD3AAAuAAQKfx4AAhEACAlMHfwZAFoCABEACAlMHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgEJAQAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8ZAAMCAAcJtAXqLgAEAQACAAcJtAXqLgAEAQABAAEJCwG5bwATAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH8kAAQTAAYJASJ0AwBmAQATAAUJgSF0AwBmAQARAAQJbhMnGADTAAAlAAIJhQ5gGwChAAAuAAQKfz4ABBMACQlOJuUCADYDABMACQkyJuUCADYDABEABwlAIDYYAGsCACUAAgmEGqM2AJ0AAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAAALgAECggJEQAAAA==.',
['Úl']='Úlfa:BAAALgAECggJEwAAAA==.',
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
