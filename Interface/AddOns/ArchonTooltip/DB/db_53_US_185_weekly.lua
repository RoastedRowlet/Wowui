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

local lookup = {'Mage-Arcane','Mage-Frost','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Warlock-Demonology','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Outlaw','Shaman-Restoration','Paladin-Holy','Monk-Brewmaster','Druid-Feral','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Windwalker','Druid-Balance','Druid-Restoration','Shaman-Elemental','Warlock-Affliction','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','DemonHunter-Havoc',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abeblinkin:BAABNQAECn8aAAIBAAcK8BHM6AC4AQABAAcK8BHM6AC4AQAAAA==.Aborlight:BAAANQAECgUIDQAAAA==.',
Ad='Adit:BAAANQAECggIDwAAAA==.',
Af='Afrit:BAABNQAECn8UAAMBAAcKYxBrawBxAQABAAcKYxBrawBxAQACAAEKPgSGUwAeAAAAAA==.',
Ai='Aiwass:BAABNQAECn8mAAIDAAoK4gU7BwAGAQADAAoK4gU7BwAGAQAAAA==.',
Al='Alieah:BAAANQAECgYIEAAAAA==.Alorum:BAAANQADCggIEAABNQAECgkJIgAEAOUNAA==.Alpharius:BAAANQAECgUIEwAAAA==.',
Am='Amacoozy:BAABNQAECn89AAIFAAkKgRkhSwCoAgAFAAkKgRkhSwCoAgAAAA==.Amathricus:BAABNQAECn8sAAIGAAgKRwm5pAAMAQAGAAgKRwm5pAAMAQAAAA==.',
Ar='Arms:BAACNQAFFH8VAAMHAAcK8xT7BADDAQAHAAcK8xT7BADDAQAIAAEKAACUJgAtAAA1AAQKfyQAAgcACgowITcNAJICAAcACgowITcNAJICAAAA.Artima:BAAANQADCgMIAwAAAA==.',
As='Ashh:BAAANQADCgcIDQAAAA==.Ashuk:BAAANQAECgQIBAAAAA==.',
At='Athena:BAAANQAECgUIDwAAAA==.',
Au='Augtism:BAEANQADCgIIAgABNQAECgcICAAJAAAAAA==.Auralei:BAAANQADCgUIBQABNQAECgQIEQAJAAAAAA==.',
Az='Azelia:BAAANQAECgQIBQABNQAECgcICgAJAAAAAA==.Azzy:BAAANQAECgcICgAAAA==.',
Be='Bellestri:BAABNQAECn8lAAIKAAkK+wROkADPAAAKAAkK+wROkADPAAAAAA==.',
Bi='Bigb:BAABNQAECn8YAAQEAAYKtiHoZAByAQAEAAYKLSDoZAByAQALAAQKCiPpDAD/AAAMAAEKAAB3lwApAAAAAA==.Bigface:BAAANQAECggIEAAAAA==.Bigrod:BAACNQAFFH8IAAINAAMKzwf0FABwAAANAAMKzwf0FABwAAA1AAQKfyQAAg0ACQr9FY4aAMABAA0ACQr9FY4aAMABAAAA.Binks:BAAANQAECgEIAgAAAA==.',
Bl='Black:BAABNQAECn8ZAAIOAAgK0hfAAQD6AQAOAAgK0hfAAQD6AQAAAA==.Blasfoomous:BAACNQAFFH8NAAINAAUK8Q/LFgD2AAANAAUK8Q/LFgD2AAA1AAQKfzgAAg0ACgohIBMKAKsCAA0ACgohIBMKAKsCAAAA.Blu:BAACNQAFFH8SAAIPAAUKRx7sCQCwAQAPAAUKRx7sCQCwAQA1AAQKfy0AAg8ACgoSJNgOAEwDAA8ACgoSJNgOAEwDAAAA.',
Bo='Bochese:BAAANQAECgMIAwABNQAECggIIwAQAPwdAA==.',
Br='Brochese:BAAANQAECgUICQABNQAECggIIwAQAPwdAA==.',
Bu='Bubblewrap:BAAANQAECgIIAwABNQAFFAUIDQARAHcUAA==.Budfoster:BAAANQADCggIEAAAAA==.',
['Bá']='Básicc:BAAANQADCgUIBQAAAA==.',
Ca='Canadianguy:BAAANQAECgQIBgABNQAECgcIGgABAPARAA==.Cappen:BAAANQADCgIIAgAAAA==.',
Ce='Cedrik:BAAANQAECgMIAwAAAA==.Ceres:BAAANQADCgMIAwAAAA==.',
Ch='Cheyeon:BAAANQAECgEIAQAAAA==.',
Cl='Classcarry:BAABNQAECn8bAAMGAAkKah99VgCzAQAGAAkKah99VgCzAQAQAAUKkhPvvAACAQABNQAECgoKIwAPANscAA==.Claybigsby:BAACNQAFFH8NAAMDAAUKyBfbCwChAAADAAIKIRbbCwChAAAKAAMKbxnHMQCTAAA1AAQKfy0AAwoACgqhH2tuABMCAAoACAqeH2tuABMCAAMABArXGv4vAAkBAAAA.Clif:BAAANQAFFAEIAQAAAA==.',
Co='Collie:BAEBNQAECn8hAAISAAoKoSOOAQAcAwASAAoKoSOOAQAcAwAAAA==.Constantina:BAABNQAECn8+AAITAAkKbxYBSwBEAgATAAkKbxYBSwBEAgAAAA==.Corven:BAAANQAECgQIBAAAAA==.',
Cr='Crunchycars:BAAANQAECgMIAwAAAA==.',
Cy='Cyleste:BAABNQAECn8hAAMUAAoKBwtxLADCAQAUAAoKBwtxLADCAQATAAQK0Q3yxADPAAAAAA==.',
De='Deadlylady:BAAANQADCgUIBQAAAA==.Demonifrita:BAAANQADCggICgAAAA==.Demonlady:BAAANQADCggIEAAAAA==.Deo:BAABNQAECn8eAAMVAAoKZxahDQDHAQAVAAkKZxahDQDHAQAQAAEKsxIGxAA2AAAAAA==.Derpy:BAABNQAECn8bAAMRAAgKvAnkCwAMAQARAAgKvAnkCwAMAQAWAAYKsQPqTQC/AAAAAA==.',
Dh='Dheevix:BAAANQAECgYICgABNQAECgoKMwABACYbAA==.',
Dj='Djheals:BAAANQAECgMIAwABNQAECggIGgAXAEANAA==.Djmuphasa:BAABNQAECn8aAAMXAAgKQA2dNgDxAAAXAAcKHwydNgDxAAAYAAUKbgXvOwCoAAAAAA==.Djthrasher:BAAANQAECgQIBgABNQAECggIGgAXAEANAA==.',
Dr='Drachese:BAAANQAECgUIBwABNQAECggIIwAQAPwdAA==.Dripps:BAAANQAECgMIAwAAAA==.Druchese:BAABNQAECn8lAAMYAAcK7hvBFQDPAQAYAAcK7hvBFQDPAQAXAAYKMg5sYwBAAQABNQAECggIIwAQAPwdAA==.',
Ea='Eagleeye:BAABNQAECn8dAAIGAAgK/QnXjAA3AQAGAAgK/QnXjAA3AQAAAA==.',
Em='Emsley:BAABNQAECn9LAAIZAAoKYRaoRQBfAgAZAAoKYRaoRQBfAgAAAA==.',
Er='Eralina:BAAANQADCgUIBQAAAA==.Erebos:BAAANQADCgEIAQAAAA==.Erised:BAAANQAECgQIBAAAAA==.',
Ev='Ev:BAABNQAECn8XAAMRAAgKeRuYDQAgAgARAAUKSCaYDQAgAgAWAAcK7hCWOQBHAQAAAA==.',
Ex='Exo:BAACNQAFFH8HAAIBAAQKlAycLgAbAQABAAQKlAycLgAbAQA1AAQKfyIAAwEACgrYH0d3AI8CAAEACgrDHUd3AI8CAAIAAgrQIQwwAH8AAAAA.',
Fa='Falorin:BAAANQAECgEIAQAAAA==.',
Fl='Floudwing:BAAANQABCgYIDAAAAA==.',
Fn='Fnwarriors:BAAANQADCgcICAAAAA==.',
Fo='Focalors:BAAANQAECgcIDwABNQAFFAUIDwABAGUVAA==.Foobear:BAAANQAECgcIEAABNQAFFAUIDQANAPEPAA==.',
Fr='Franchescold:BAAANQAECggICwAAAA==.',
Fu='Furlock:BAABNQAECn8dAAIaAAgKpRmlAgAcAgAaAAgKpRmlAgAcAgAAAA==.',
Ga='Gabriel:BAACNQAFFH8HAAIVAAIK0QDRDQAoAAAVAAIK0QDRDQAoAAA1AAQKf2QAAxUACgpIFrcNAMUBABUACgpIFrcNAMUBAAYAAgoAAGzAASgAAAAA.Galicia:BAAANQAECgcIEwAAAA==.Gantaris:BAABNQAECn8fAAMYAAoK+A+tEgD8AQAYAAoK+A+tEgD8AQAXAAEKAABChAAAAAAAAA==.Garbagevoker:BAAANQAECgIIAgAAAA==.Gaymer:BAAANQAECgQIBwABNQAECgUIDwAJAAAAAA==.',
Gi='Gir:BAAANQAECgYIEQAAAA==.',
Gl='Glochese:BAAANQADCggIDwABNQAECggIIwAQAPwdAA==.Glurp:BAAANQAECgYIBgAAAA==.',
Go='Gochese:BAABNQAECn8jAAMQAAgK/B1oKwC6AgAQAAgK/B1oKwC6AgAGAAIK7AjJRgEzAAAAAA==.Gorgeous:BAAANQAECgYIBgABNQAECggIEAAJAAAAAA==.Gothel:BAAANQAECgUIBQAAAA==.',
Gr='Grace:BAAANQAECgcIDAAAAA==.Greenseer:BAAANQAECgcIDwAAAA==.',
Gt='Gtoffmyd:BAAANQADCgIIAgABNQAECgUIBQAJAAAAAA==.Gtoffmydruid:BAAANQAECgUIBQAAAA==.Gtoffmyface:BAAANQADCgUIBQABNQAECgUIBQAJAAAAAA==.',
Gw='Gwaralmighty:BAABNQAECn86AAIbAAoKxR4jBAA+AgAbAAoKxR4jBAA+AgAAAA==.',
Gy='Gypo:BAAANQADCggIFgAAAA==.',
Ha='Haagen:BAABNQAECn8tAAIEAAoKzQ7SRADRAQAEAAoKzQ7SRADRAQAAAA==.Hamsup:BAABNQAECn8qAAIFAAoKdxQThAARAgAFAAoKdxQThAARAgAAAA==.Hatch:BAAANQADCgcICAABNQAECggIFwARAHkbAA==.',
['Hô']='Hôldem:BAEBNQAECn8qAAIXAAgKVw9DLAArAQAXAAgKVw9DLAArAQAAAA==.',
Ic='Icylady:BAAANQADCgYIDAAAAA==.',
If='Ifrita:BAABNQAECn8vAAIBAAkKLBEQXwCQAQABAAkKLBEQXwCQAQAAAA==.Ifrite:BAAANQAECgEIAQAAAA==.',
Ik='Ikur:BAAANQAECgYICwABNQAECgoKNgAQAGgcAA==.',
Im='Imbasoul:BAAANQADCgMIAwAAAA==.Imyerchese:BAAANQADCgYIBgABNQAECggIIwAQAPwdAA==.',
Jo='Jontalo:BAAANQADCgcIDgAAAA==.Jormi:BAABNQAECn8cAAIFAAcK1B9+XAB2AgAFAAcK1B9+XAB2AgAAAA==.',
Ju='Justthetipp:BAAANQAECgMIAwABNQAECgcIFQAZADcPAA==.',
Ka='Kaerlyn:BAAANQADCgQIBAAAAA==.Kalthael:BAAANQABCgYICQAAAA==.Karthus:BAAANQADCgEIAQAAAA==.Kasaurus:BAAANQADCgMIAQAAAA==.Kasura:BAABNQAECn8tAAMSAAoKSRz+CAC+AgASAAoKSRz+CAC+AgAYAAQKNRhRTADdAAAAAA==.',
Kh='Kharahealer:BAAANQAECgMIAwAAAA==.',
Ki='Kindred:BAAANQADCgYICQAAAA==.Kirihax:BAABNQAECn8YAAIUAAgKLBzqHQBRAgAUAAgKLBzqHQBRAgABNQAFFAcIGgAWACkdAA==.',
Ko='Kochese:BAAANQAECgUIBQABNQAECggIIwAQAPwdAA==.',
Ku='Kutar:BAAANQAECgQIBgAAAA==.',
Li='Limedro:BAAANQADCgcIFAAAAA==.Limpdaddy:BAAANQAECgIIAgAAAA==.',
Lo='Lochese:BAAANQADCgYIDAABNQAECggIIwAQAPwdAA==.Lockme:BAAANQAECgcICgABNQAFFAcIHwABAJ0aAA==.Lotei:BAAANQADCgMIAwAAAA==.',
Ma='Magicdro:BAAANQADCgQIBAAAAA==.Magorrak:BAAANQAECgUICQAAAA==.Mal:BAACNQAFFH8YAAMcAAcKth5PAQBpAQAcAAYKqCJPAQBpAQAdAAIK8Q55FwBYAAA1AAQKfx0AAx0ACgrgIbodAOUBAB0ACAqqHrodAOUBABwABAp7JsIkAOMAAAAA.Marxwomun:BAAANQAECgQIBAAAAA==.Mary:BAACNQAFFH8XAAIcAAYKYh+1AADiAQAcAAYKYh+1AADiAQA1AAQKfyoAAhwACgr9I4EHAFsDABwACgr9I4EHAFsDAAAA.',
Mc='Mcshammer:BAAANQAECgQIDAAAAA==.',
Me='Medis:BAAANQADCgQIBAAAAA==.Mero:BAAANQAECgQICAAAAA==.Metal:BAABNQAECn8kAAIeAAgKrxmAAgD/AQAeAAgKrxmAAgD/AQAAAA==.',
Mi='Minervajt:BAAANQAECgYIEgAAAA==.Miorine:BAACNQAFFH8PAAMBAAUKZRVNIACFAQABAAUKZRVNIACFAQACAAEKzwKuFgA4AAA1AAQKfy4AAgEACgpHHtM1AB4DAAEACgpHHtM1AB4DAAAA.Mistbehavin:BAACNQAFFH8NAAIRAAUKdxTLBQAVAQARAAUKdxTLBQAVAQA1AAQKf0UAAhEACgpOH6gCAH8CABEACgpOH6gCAH8CAAAA.',
Mo='Moginndar:BAABNQAECn8nAAMVAAkKDg8DKQCVAQAVAAkKUg4DKQCVAQAGAAUKhg95AwEZAQAAAA==.Mok:BAAANQAFFAIIAgAAAA==.Moochese:BAAANQAECgUIEgABNQAECggIIwAQAPwdAA==.',
Mu='Muggsy:BAAANQAECgEIAQAAAA==.Munidar:BAABNQAECn8dAAIfAAgKPQgLEQB3AQAfAAgKPQgLEQB3AQAAAA==.',
My='Mytz:BAAANQAECgMIAwAAAA==.',
['Mï']='Mïnna:BAABNQAECn8sAAMIAAoKxiD/EAAvAwAIAAoKvSD/EAAvAwAHAAcKsxtqMwARAgABNQAFFAMICAAXAB4PAA==.',
Ne='Nemisai:BAAANQADCggIEwAAAA==.',
On='Onebuttonwin:BAAANQADCgMIAwAAAA==.',
Op='Optimizer:BAABNQAECn8gAAMgAAgKLwq7DwBCAQAgAAgKLwq7DwBCAQAhAAQKrALzGABZAAAAAA==.',
Or='Orionbtch:BAAANQADCgYIDgAAAA==.',
Ov='Overheat:BAABNQAECn8WAAIBAAkKRRRp3QDNAQABAAkKRRRp3QDNAQAAAA==.',
Po='Poppy:BAAANQAECggIEQAAAA==.Portinglol:BAAANQAECgEIAQABNQAECgoKIwAPANscAA==.',
Pr='Problem:BAAANQADCgIIAgAAAA==.',
Pu='Pugne:BAABNQAECn8fAAMGAAoKaRcQiQAVAgAGAAoKaRcQiQAVAgAQAAEKXwvfxgAzAAAAAA==.',
Qu='Qué:BAAANQABCgQIBAAAAA==.',
Ra='Ratidari:BAABNQAECn8UAAIiAAYKthl9MwCmAQAiAAYKthl9MwCmAQAAAA==.Ratshifter:BAABNQAECn8cAAMSAAgKKRZ4EgDWAQASAAcK3Bh4EgDWAQAXAAcKtgpKOwDZAAABNQAECgYIFAAiALYZAA==.Ravenstorm:BAAANQAECgQIBAAAAA==.',
Re='Red:BAAANQAECgQIBQABNQAECgoKJAAXACsUAA==.Remmîngton:BAAANQAECgUICwAAAA==.Retbulls:BAABNQAECn8qAAIGAAoKViEQIQCHAgAGAAoKViEQIQCHAgAAAA==.',
Rh='Rhynehardt:BAAANQADCgYIBgAAAA==.',
Ri='Riptidedro:BAACNQAFFH8FAAIPAAIKlg5nIwCAAAAPAAIKlg5nIwCAAAA1AAQKfzQAAg8ACgqRHVwaAAcDAA8ACgqRHVwaAAcDAAAA.',
Ru='Runslikedeer:BAABNQAECn8jAAIYAAgKtBleFQDVAQAYAAgKtBleFQDVAQAAAA==.Runé:BAAANQAECgEIAQABNQAECgQICQAJAAAAAA==.',
Sa='Satorugojo:BAAANQABCgIIAgAAAA==.',
Se='Sean:BAACNQAFFH8NAAMBAAUKVw4vLQAmAQABAAUKVw4vLQAmAQACAAEK1wMtFQBCAAA1AAQKf0IAAwEACgqpH3seAIICAAEACgqpH3seAIICAAIAAgr6E1YoAEcAAAAA.Serah:BAACNQAFFH8LAAIjAAUKcwsmDwAWAQAjAAUKcwsmDwAWAQA1AAQKfywAAyMACgoAFoUnAFsBACIACArWB/M5AHYBACMACQoAFoUnAFsBAAAA.Sevia:BAAANQAECgIIBAAAAA==.',
Sh='Sheppy:BAAANQAECgUICAAAAA==.Shimakaze:BAABNQAECn8VAAMIAAgK9B1IHADiAgAIAAgK9B1IHADiAgANAAQKZBXVggDxAAABNQAFFAUIDwABAGUVAA==.Shizaam:BAACNQAFFH8NAAMPAAUKyg7cEgAkAQAPAAUKyg7cEgAkAQAZAAMKtAkCHQDXAAA1AAQKfzgAAxkACgrUIXcgAAkDABkACQpsIncgAAkDAA8ACQp+HP8uAKUCAAAA.Shlommy:BAABNQAECn8bAAMKAAcKmQ/okQC6AQAKAAcKmQ/okQC6AQADAAEKmwCFigAOAAAAAA==.',
Si='Silvermage:BAACNQAFFH8fAAIBAAcKnRpyCQAyAgABAAcKnRpyCQAyAgA1AAQKfy8AAgEACgo2JU4JAA4DAAEACgo2JU4JAA4DAAAA.Sinfxl:BAAANQAECgQICQAAAA==.Sinheph:BAAANQAECgQIBwAAAA==.Sippinsizurp:BAABNQAECn8hAAIBAAkKLB9lSwDrAgABAAkKLB9lSwDrAgAAAA==.',
Sk='Skullmages:BAABNQAECn8kAAIGAAoK9B5RJAA0AwAGAAoK9B5RJAA0AwAAAA==.',
Sl='Slayur:BAAANQAECgcICAAAAA==.Sloppydro:BAABNQAECn82AAMQAAoKPBM0JAApAgAQAAoKPBM0JAApAgAGAAIKdwWAhQFSAAAAAA==.',
Sm='Smuckerz:BAAANQAECgEIAgAAAA==.',
So='Socksimus:BAAANQADCgcIGAAAAA==.Sockssham:BAAANQADCggICAAAAA==.Sotari:BAAANQADCggICAAAAA==.',
St='Stabberz:BAABNQAECn9LAAIcAAoK4h+YCgA2AwAcAAoK4h+YCgA2AwAAAA==.Stannane:BAAANQADCgUICQABNQAECgQIBgAJAAAAAA==.Stellaloona:BAAANQAECgEIAQAAAA==.Sticks:BAAANQADCgcICQAAAA==.Stinkyhooves:BAEANQADCgQIBgABNQAECgcICAAJAAAAAA==.Stromboli:BAAANQADCgUIBQABNQAECgQIBwAJAAAAAA==.',
Su='Sushiroll:BAABNQAECn8jAAMPAAoK2xzOCgAWAwAPAAoK2xzOCgAWAwAZAAUKERfGngBZAQAAAA==.',
Sw='Sweetsourrex:BAAANQAECgUIBAABNQAECgoKQgAdAOkhAA==.',
Ta='Tamaqua:BAABNQAECn8YAAIPAAgK1xBFhACAAQAPAAgK1xBFhACAAQAAAA==.Tatisjr:BAAANQAECgIIAwABNQAECgMIAwAJAAAAAA==.',
Te='Telissa:BAAANQAECgEIAQAAAA==.Temoin:BAAANQAECgMIBQAAAA==.',
Th='Thalor:BAAANQAECgQIBAAAAA==.Thrass:BAABNQAECn8XAAICAAoKuBFPCgAlAgACAAoKuBFPCgAlAgAAAA==.Throngler:BAAANQAECgEIAQABNQAECgkJGAAMAFwRAA==.',
To='Toobrunner:BAAANQAECgcIDAAAAA==.',
Tr='Trueknight:BAAANQADCgEIAQAAAA==.',
Un='Unholeytoast:BAAANQAECgYICwABNQAFFAUIDQAPAMoOAA==.',
Va='Vampress:BAAANQAECgMIBAAAAA==.Variam:BAABNQAECn8jAAIEAAgKjhbaUQCnAQAEAAgKjhbaUQCnAQAAAA==.',
Ve='Velannis:BAABNQAECn8uAAQOAAoKUiDtBACvAgAOAAgKOh/tBACvAgAdAAkK9xqhKQDdAQAcAAcKSRxQSQCeAQAAAA==.',
Vo='Voidangel:BAAANQAECgMIAwAAAA==.Vonder:BAAANQAECgQICAAAAA==.Voodooki:BAAANQAECgIIAgAAAA==.',
Vu='Vuo:BAABNQAECn8iAAIEAAkK5Q2bTQC0AQAEAAkK5Q2bTQC0AQAAAA==.',
Wi='Winze:BAAANQADCggIDgAAAA==.Withdraw:BAAANQADCgUIBQAAAA==.',
Wo='Wochese:BAAANQAECgQIBAABNQAECggIIwAQAPwdAA==.',
Wr='Wrath:BAAANQADCggIDAABNQAECgUIDwAJAAAAAA==.',
Wu='Wuchese:BAAANQAECgMIAwABNQAECggIIwAQAPwdAA==.',
Xf='Xfreshh:BAAANQAECgYICQAAAA==.',
Ya='Yamaa:BAAANQAECgUIBgABNQAFFAQICwABAA0OAA==.Yamadono:BAABNQAECn8WAAMdAAoKzh5JDADUAgAdAAkKnh5JDADUAgAcAAUKxxxoMACtAAABNQAFFAQICwABAA0OAA==.Yamalock:BAAANQAECgEIAQABNQAFFAQICwABAA0OAA==.Yamá:BAAANQADCgcIBwABNQAFFAQICwABAA0OAA==.Yamå:BAACNQAFFH8LAAIBAAQKDQ4jGgDdAAABAAQKDQ4jGgDdAAA1AAQKfywAAgEACgpmH8dKAOwCAAEACgpmH8dKAOwCAAAA.',
Yi='Yingzhi:BAAANQADCgIIAgAAAA==.',
Za='Zapchese:BAABNQAECn8WAAMPAAYK+hvnYADrAQAPAAYK+hvnYADrAQAZAAYKBQ8FkQB6AQABNQAECggIIwAQAPwdAA==.',
Zo='Zortok:BAAANQAECgcICwAAAA==.',
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
