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

local lookup = {'Paladin-Protection','Priest-Holy','Unknown-Unknown','Warrior-Arms','Druid-Restoration','Mage-Arcane','Druid-Balance','Mage-Frost','Mage-Fire','Paladin-Retribution','Evoker-Preservation','Warlock-Demonology','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','Druid-Feral','Shaman-Elemental','Hunter-Survival','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Priest-Shadow','Priest-Discipline','Paladin-Holy','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','Warlock-Affliction','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abjured:BAAANQABCgIIAgABNQAECgkJHwABAJsUAA==.Absolu:BAAANQAECgEIAQAAAA==.',
An='Anaibubble:BAAANQADCggICQAAAA==.',
Ar='Ariadné:BAABNQAECn8VAAICAAgKuhnoPwBrAgACAAgKuhnoPwBrAgAAAA==.Arialla:BAAANQAECgUICwABNQABCgQICAADAAAAAA==.Arin:BAAANQAECgEIAQABNQAECgoKHgAEAOwXAA==.',
Az='Azalan:BAAANQADCgUIBQABNQAECgoKHQAFABAUAA==.',
Ba='Bandiaz:BAABNQAECn8fAAIGAAcKpRLpswArAQAGAAcKpRLpswArAQAAAA==.Banson:BAAANQAECgIIAgAAAA==.Bastusi:BAAANQAECgMIAwAAAA==.',
Be='Bearlover:BAAANQAECgQIBgAAAA==.Bellatrixx:BAABNQAECn8dAAIHAAYKWQblXgCWAAAHAAYKWQblXgCWAAAAAA==.',
Bl='Blighted:BAAANQADCgYIBgABNQAECgkJHwABAJsUAA==.',
Bo='Bootles:BAABNQAECn8VAAQIAAgKuBnZDwCqAQAGAAYKFxIR6gC2AQAIAAYKcRXZDwCqAQAJAAIK7B6nBwC5AAAAAA==.Bowl:BAAANQADCgYIGAAAAA==.',
Bu='Bullwings:BAABNQAECn84AAIKAAoKmSLcFQAFAwAKAAoKmSLcFQAFAwAAAA==.Burnin:BAABNQAECn8XAAILAAgKGQ/IHwDYAQALAAgKGQ/IHwDYAQAAAA==.',
Ch='Charrend:BAABNQAECn8jAAIBAAgKFgOdPwCYAAABAAgKFgOdPwCYAAAAAA==.',
Co='Cobalt:BAACNQAFFH8KAAIMAAYKexHoDgAgAQAMAAYKexHoDgAgAQA1AAQKfzsAAgwACgr8IdcXACkDAAwACgr8IdcXACkDAAAA.Coco:BAAANQADCggICAABNQAECgoKHQAFABAUAA==.Codus:BAAANQAECgcIDAAAAA==.',
Cr='Crazon:BAAANQADCgYIEQAAAA==.',
Ct='Cthulhu:BAABNQAECn8YAAIMAAkK0xmzdABoAQAMAAkK0xmzdABoAQAAAA==.',
Da='Damndalion:BAAANQABCgQIBAAAAA==.Darkdworf:BAACNQAFFH8RAAINAAUKUiWUCQDBAQANAAUKUiWUCQDBAQA1AAQKfzMAAg0ACgpMJaUHAIEDAA0ACgpMJaUHAIEDAAAA.Darner:BAAANQADCggIEQAAAA==.',
De='Debuff:BAAANQAECgMICgABNQAECgoKRAAOAEslAA==.',
Do='Doomradicals:BAAANQAECgUIDwAAAA==.Doriian:BAAANQADCggIEQAAAA==.',
Dr='Dragothu:BAAANQAECgIIBQABNQAECgoKOAAKAJkiAA==.Druidbelly:BAABNQAECn85AAMPAAoK1B9vBgDfAgAPAAoK1B9vBgDfAgAQAAEKQAhnSQAnAAAAAA==.',
Du='Dushlan:BAABNQAECn8WAAIRAAcKvghlnQBcAQARAAcKvghlnQBcAQAAAA==.Dutton:BAAANQAECgEIAQAAAA==.',
Ea='Eatsbabies:BAAANQAECgMIAwAAAA==.',
Ei='Eiskält:BAAANQAECgIIAgAAAA==.',
En='Endrin:BAAANQAECgQIBgAAAA==.',
Ew='Eww:BAEBNQAECn8UAAMOAAgKSxozVgBvAgAOAAgKIhozVgBvAgASAAMK7xNmDQDrAAAAAA==.',
Fe='Fedelia:BAAANQAECgEIAQAAAA==.Federica:BAAANQAECgEIAQAAAA==.Felladin:BAAANQAECgYIEwABNQAFFAYIDwAFAPEXAA==.Felldeeds:BAACNQAFFH8PAAIFAAYK8RdZBQClAQAFAAYK8RdZBQClAQA1AAQKfy4AAgUACgpAIXAKACEDAAUACgpAIXAKACEDAAAA.Fent:BAACNQAFFH8SAAITAAYK1x5NCADMAQATAAYK1x5NCADMAQA1AAQKf0kAAhMACgrRIlcFAJwDABMACgrRIlcFAJwDAAAA.',
Fi='Fingerboppin:BAAANQAECgEIAwABNQAECgoKOwANAFYlAA==.Fingerr:BAAANQAECgUIBQABNQAECgoKOwANAFYlAA==.Fingers:BAABNQAECn87AAINAAoKViVIAwBQAwANAAoKViVIAwBQAwAAAA==.Fitforakìng:BAABNQAECn8fAAIBAAkKmxSnIQDWAQABAAkKmxSnIQDWAQAAAA==.',
Fo='Foxxopally:BAAANQADCggIEAAAAA==.',
Fr='Freak:BAAANQADCgQIBAAAAA==.Froztbane:BAEANQAECgIIAwABNQAFFAcIFAAUAA8VAA==.Froztbanshee:BAECNQAFFH8UAAIUAAcKDxUBAwB5AQAUAAcKDxUBAwB5AQA1AAQKf34ABBQACgp5JbsCAEYDABQACgp5JbsCAEYDABUACQpuF6MGABwCABYAAQqWD1eRADgAAAAA.',
Gi='Girthatbirth:BAABNQAECn8dAAIXAAoK2BNiIwAjAgAXAAoK2BNiIwAjAgABNQAECgoKMAARAEweAA==.',
Gl='Glass:BAABNQAECn8wAAIOAAoKBBnCNgBeAgAOAAoKBBnCNgBeAgAAAA==.',
Go='Goatsnake:BAAANQADCggICAAAAA==.Goth:BAAANQADCgQIBAAAAA==.',
Gr='Grimmadin:BAAANQADCgEJAQAAAA==.Grimmsaw:BAAANQAECgEJAQAAAA==.Grudge:BAAANQAECgYIEQABNQAECgoKHwARAFYOAA==.Grudgetotem:BAABNQAECn8fAAIRAAoKVg7SRgCiAQARAAoKVg7SRgCiAQAAAA==.',
Gu='Gullskull:BAAANQAECgQIBAAAAA==.',
Ha='Hanzoh:BAAANQAECgMIAwABNQAECgoKRAAOAEslAA==.Harrowhark:BAACNQAFFH8FAAIXAAIKnA+MFQCEAAAXAAIKnA+MFQCEAAA1AAQKfywAAxcACgoAHQMlAGsCABcACgoAHQMlAGsCABgABArIGTWZAM4AAAAA.Haveheart:BAAANQAECgEIAgABNQAECgkJHwABAJsUAA==.',
He='Herambae:BAAANQADCgEIAQAAAA==.Herculesàtan:BAAANQADCgEIAQAAAA==.Herculesátan:BAAANQADCgYIBgAAAA==.',
Ho='Holybelly:BAAANQAECgEIAQABNQAECgoKOQAPANQfAA==.Honeyt:BAAANQAECgYICAAAAA==.',
Hu='Huntundra:BAABNQAECn8aAAMOAAoKxQSQ0gDyAAAOAAgKPgWQ0gDyAAAZAAYKbAHlaACJAAAAAA==.',
Hy='Hyacinth:BAABNQAECn9GAAIHAAoKaxWPHAAMAgAHAAoKaxWPHAAMAgAAAA==.',
Ia='Iamomegafox:BAACNQAFFH8KAAIaAAYKqA4IEADrAAAaAAYKqA4IEADrAAA1AAQKfzgAAxoACgpYIuECABoDABoACQpYIuECABoDABsABgqeCaMxADABAAAA.',
Ic='Icychill:BAAANQADCgUIBwAAAA==.',
Ig='Ignax:BAACNQAFFH8TAAILAAYK3Qr5CAB7AQALAAYK3Qr5CAB7AQA1AAQKfzUAAgsACgrfGP8SAH0CAAsACgrfGP8SAH0CAAAA.',
Im='Imomeganisha:BAAANQADCggIEAABNQAFFAYICgAaAKgOAA==.',
In='Infoxxocated:BAAANQAECggIEAAAAA==.Innerhope:BAABNQAECn8yAAQCAAoKyyHmHQD5AgACAAoKyyHmHQD5AgAcAAQKHQ6vTgDZAAAdAAQKpwe2FwC3AAAAAA==.Inspired:BAAANQAECgMIAgABNQAECgkJHwABAJsUAA==.',
Io='Ionias:BAABNQAECn8bAAQKAAcK0ReTigCiAQAKAAcK0ReTigCiAQABAAMKGwn3WAB6AAAeAAEKeAOcKQEsAAAAAA==.',
Je='Jevik:BAAANQADCgEIAQAAAA==.',
Jo='Johadan:BAABNQAECn8YAAIKAAgKpQRABwETAQAKAAgKpQRABwETAQAAAA==.Jonwane:BAABNQAECn8YAAIQAAgK7Q1vGwATAQAQAAgK7Q1vGwATAQAAAA==.',
Ka='Kaelx:BAAANQAECgEIBQAAAA==.Kagnara:BAAANQADCgIJAgABNQAFFAIIBQAXAJwPAA==.',
Ke='Keely:BAAANQAECgQICgAAAA==.',
Kh='Khalyia:BAAANQADCgYIDAAAAA==.',
Ki='Kiirabi:BAAANQADCggICAABNQAFFAkJHAAFAFsaAA==.Kirakitsune:BAAANQADCgcICAAAAA==.',
Kr='Krydunk:BAAANQADCgIIAgAAAA==.',
Ky='Kyle:BAAANQAECggIAQAAAA==.',
Li='Lione:BAAANQAECgQIBgAAAA==.',
Lo='Lorelei:BAAANQADCgMIAwAAAA==.',
Ly='Lyandra:BAAANQABCggIGAAAAA==.',
['Lì']='Lìllyanna:BAABNQAECn8uAAIBAAkKQhngFgBFAgABAAkKQhngFgBFAgAAAA==.',
Ma='Magmara:BAAANQADCgcJBwABNQAFFAIIBQAXAJwPAA==.Magustero:BAAANQAECgQICAAAAA==.',
Me='Melithia:BAAANQADCgUIBQAAAA==.Meowhunter:BAAANQAECgUIAwAAAA==.',
Mi='Miami:BAAANQAECgYIEAABNQAFFAcIGAAfAHwaAA==.Miaraa:BAAANQAECgQIBgAAAA==.Mithos:BAAANQADCgYIBgAAAA==.',
Mu='Murgold:BAAANQAECgcIDQAAAA==.',
My='Myssiadina:BAAANQABCgQIBwAAAA==.',
Na='Nayru:BAAANQAECgUIBgABNQAFFAIIBQAXAJwPAA==.',
Ne='Necrolyte:BAAANQAECgEIAgABNQAECgkJGAAMANMZAA==.Ned:BAEBNQAECn9DAAIEAAoK1iZSAACgAwAEAAoK1iZSAACgAwABNQAFFAIIBgACAI0mAA==.',
Ni='Ninax:BAABNQAECn8dAAIOAAkKZhn1PwBDAgAOAAkKZhn1PwBDAgAAAA==.',
No='Notcodus:BAAANQADCgUIBgAAAA==.',
Oc='Octomore:BAAANQAECgUIBgAAAA==.',
On='Onlydreams:BAAANQAECggIDAAAAA==.',
Pa='Pandamoniium:BAAANQAECggIEgABNQAECgoKRQAGAIQhAA==.Pandamonk:BAABNQAECn8oAAMgAAoKzyMUAQBGAwAgAAoKzyMUAQBGAwAhAAUKYgtQTgC9AAABNQAFFAUIEQANAFIlAA==.',
Pe='Percy:BAEANQADCgcICQAAAA==.',
Ph='Phoeníx:BAAANQADCgYIDAAAAA==.',
Pi='Picklejuice:BAAANQABCgIIAQAAAA==.Pickleswag:BAAANQAECgQIBQABNQAECgoKMAARAEweAA==.',
Pl='Plagued:BAAANQADCgUIBQABNQAECgkJHwABAJsUAA==.',
Po='Powliden:BAAANQADCgIIBAAAAA==.',
Pr='Preservation:BAAANQAFFAIIAgAAAA==.',
Pt='Ptulatha:BAAANQABCgEIAQAAAA==.',
Ra='Radagast:BAACNQAFFH8FAAIHAAIKNA1iGQCHAAAHAAIKNA1iGQCHAAA1AAQKfzIAAgcACgrPE3Q/AP8BAAcACgrPE3Q/AP8BAAAA.Radiantbug:BAABNQAECn8pAAIKAAoKIRghUQAoAgAKAAoKIRghUQAoAgAAAA==.Radicals:BAAANQAECgMIBQAAAA==.',
Re='Revna:BAAANQAECgQIBgAAAA==.',
Rh='Rhoem:BAABNQAECn8sAAMNAAoKehcqGAA0AgANAAoKehcqGAA0AgAXAAQK0xOGfwCsAAAAAA==.',
Ri='Ripca:BAABNQAECn8eAAIFAAoKmB8yBQCLAwAFAAoKmB8yBQCLAwABNQAFFAkJFAAeALcUAA==.',
Ro='Rouge:BAAANQAECgIIAgABNQAECgoKRAAOAEslAA==.',
Sa='Sandster:BAAANQAECgcICgAAAA==.',
Sc='Scapeghost:BAAANQADCgYIBgAAAA==.',
Sh='Shalendris:BAAANQAECgEIAQAAAA==.Shalestrasz:BAAANQAECggIDgAAAA==.Shochu:BAAANQAECgQIBgAAAA==.',
Sl='Slambiosis:BAEANQADCgEIAQABNQAECgkJGgAeAG4UAA==.',
Sn='Snuggle:BAAANQADCgUIBQAAAA==.',
Sp='Sp:BAACNQAFFH8WAAICAAgKhQwACAAcAgACAAgKhQwACAAcAgA1AAQKf04AAgIACgpVIhcHAIwDAAIACgpVIhcHAIwDAAAA.Sparrow:BAAANQADCgIIAgABNQAECgoKNQAiABMPAA==.Sphene:BAAANQAECgIIBQAAAA==.',
St='Stablemaster:BAAANQAECgEIAQAAAA==.Steelhi:BAAANQABCgIIAgAAAA==.Strongside:BAAANQAECgEIAQABNQAECgkJHwABAJsUAA==.',
Su='Sunshine:BAAANQAECgUIBQABNQAECgkJHwABAJsUAA==.',
Sw='Switchfoot:BAABNQAECn8XAAMjAAcK+BhcDACSAQAaAAcKdBXjRQCvAQAjAAYKfBdcDACSAQAAAA==.',
Sy='Syleria:BAAANQAECgYICgAAAA==.',
Ta='Tale:BAECNQAFFH8KAAIRAAQKMwoxFAC9AAARAAQKMwoxFAC9AAA1AAQKf04AAhEACgqLHfUmAOcCABEACgqLHfUmAOcCAAE1AAQKCAgUAA4ASxoA.Tankard:BAAANQADCgEIAQABNQAECgkJHwABAJsUAA==.',
To='Toyotaavalon:BAAANQADCgYICAABNQAECgoKMAARAEweAA==.Toyotacamry:BAABNQAECn8wAAMRAAoKTB6XLgALAgAkAAcKKhyrFQAOAgARAAoK/xyXLgALAgAAAA==.Toyotatundra:BAAANQAECgQIBwABNQAECgoKMAARAEweAA==.',
Up='Upliftw:BAAANQAECgEIAQAAAA==.',
Va='Vamana:BAAANQAECgEIAgABNQAECgoKRAAOAEslAA==.',
Ve='Velf:BAABNQAECn8WAAIUAAoKLBZmHgCcAQAUAAoKLBZmHgCcAQABNQAECgoKOAAKAJkiAA==.Velzard:BAAANQABCgEIAQAAAA==.',
Vi='Violash:BAABNQAECn8iAAIfAAoKbCOMAgCLAwAfAAoKbCOMAgCLAwAAAA==.',
['Vö']='Vöre:BAAANQADCgEJAQAAAA==.',
Wh='Whitessin:BAAANQADCgcICAAAAA==.Whýý:BAAANQADCggIFAAAAA==.',
Wi='Wireless:BAAANQABCgYIDAAAAA==.',
Yo='Yofoxxo:BAACNQAFFH8UAAIeAAgK7BMfBABIAgAeAAgK7BMfBABIAgA1AAQKfzcAAh4ACgp3JFkJAH8DAB4ACgp3JFkJAH8DAAAA.',
Ys='Ysayle:BAAANQADCgMIAwAAAA==.',
Za='Zakariahh:BAAANQADCgYIBgAAAA==.Zarea:BAABNQAECn8cAAMKAAgKOxoSfgAuAgAKAAgKAxYSfgAuAgABAAQKJh9COAApAQAAAA==.Zarlon:BAABNQAECn8bAAIKAAoKfh6HIgDNAgAKAAoKfh6HIgDNAgABNQAECgoKRAAOAEslAA==.',
Ze='Zengriff:BAABNQAECn8lAAIgAAcKdyTsBABNAgAgAAcKdyTsBABNAgAAAA==.Zerena:BAAANQAECgEIAQAAAA==.',
Zu='Zucarithas:BAABNQAECn8yAAMeAAoKvQ7vQgD1AQAeAAoKvQ7vQgD1AQAKAAMKZwjSXwFYAAAAAA==.',
['År']='Årthás:BAAANQAECgIIAgAAAA==.',
['Æl']='Ælyse:BAAANQAECgYIBgAAAA==.',
['Øv']='Øvertime:BAAANQAECggIBgAAAA==.',
['ßl']='ßluebell:BAAANQADCgMIAwAAAA==.',
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
