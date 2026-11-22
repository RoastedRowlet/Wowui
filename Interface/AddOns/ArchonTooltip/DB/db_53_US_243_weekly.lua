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

local lookup = {'Paladin-Protection','Unknown-Unknown','Druid-Restoration','Mage-Arcane','Druid-Balance','Mage-Frost','Mage-Fire','Paladin-Retribution','Evoker-Preservation','Warlock-Demonology','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','Druid-Feral','Shaman-Elemental','Hunter-Survival','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Monk-Brewmaster','Monk-Windwalker','Warlock-Affliction','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abjured:BAAANQABCgIIAgABNQAECgkJIgABAFYWAA==.Absolu:BAAANQABCgcICQABNQADCgMIAwACAAAAAA==.',
An='Anaibubble:BAAANQADCggICQAAAA==.',
Ar='Ariadné:BAAANQAECgcIEwAAAA==.Arialla:BAAANQAECgUICgABNQABCgQICAACAAAAAA==.',
Az='Azalan:BAAANQADCgUIBQABNQAECgoKHQADABAUAA==.',
Ba='Bandiaz:BAABNQAECn8gAAIEAAgKPxGtngBnAQAEAAgKPxGtngBnAQAAAA==.Banson:BAAANQAECgIIAgAAAA==.Bastusi:BAAANQAECgMIAwAAAA==.',
Be='Bearlover:BAAANQAECgQIBgAAAA==.Bellatrixx:BAABNQAECn8dAAIFAAYKWQYPZACWAAAFAAYKWQYPZACWAAAAAA==.',
Bl='Blighted:BAAANQADCgYIBgABNQAECgkJIgABAFYWAA==.',
Bo='Bootles:BAABNQAECn8VAAQGAAgKuBnZDwCqAQAEAAYKFxIR6gC2AQAGAAYKcRXZDwCqAQAHAAIK7B6nBwC5AAAAAA==.Bowl:BAAANQADCgYIGAAAAA==.',
Bu='Bullwings:BAABNQAECn88AAIIAAoKmSKMFwAEAwAIAAoKmSKMFwAEAwAAAA==.Burnin:BAABNQAECn8XAAIJAAgKGQ/IHwDYAQAJAAgKGQ/IHwDYAQAAAA==.',
Ch='Charrend:BAABNQAECn8jAAIBAAgKFgPeQwCYAAABAAgKFgPeQwCYAAAAAA==.',
Co='Cobalt:BAACNQAFFH8KAAIKAAYKexFWEwBhAQAKAAYKexFWEwBhAQA1AAQKfzsAAgoACgr8IdcXACkDAAoACgr8IdcXACkDAAAA.Coco:BAAANQADCggICAABNQAECgoKHQADABAUAA==.Codus:BAAANQAECgcICwAAAA==.',
Cr='Crazon:BAAANQADCgYIEQAAAA==.',
Ct='Cthulhu:BAABNQAECn8YAAIKAAkK0xnSfgBkAQAKAAkK0xnSfgBkAQAAAA==.',
Da='Damndalion:BAAANQABCgQIBAAAAA==.Darkdworf:BAACNQAFFH8RAAILAAUKUiWUCQDBAQALAAUKUiWUCQDBAQA1AAQKfzMAAgsACgpMJaUHAIEDAAsACgpMJaUHAIEDAAAA.Darner:BAAANQADCggIEQAAAA==.',
De='Debuff:BAAANQAECgMIBwABNQAFFAIIBAAMAH8YAA==.',
Do='Doomradicals:BAAANQAECgUIDAAAAA==.Doriian:BAAANQADCggIEQAAAA==.',
Dr='Dragothu:BAAANQAECgIIAwABNQAECgoKPAAIAJkiAA==.Druidbelly:BAABNQAECn85AAMNAAoK1B8lBwDcAgANAAoK1B8lBwDcAgAOAAEKQAhnSQAnAAAAAA==.',
Du='Dushlan:BAABNQAECn8WAAIPAAcKvghlnQBcAQAPAAcKvghlnQBcAQAAAA==.Dutton:BAAANQABCggIFAAAAA==.',
Ea='Eatsbabies:BAAANQAECgMIAwAAAA==.',
Ei='Eiskält:BAAANQAECgIIAgAAAA==.',
En='Endrin:BAAANQAECgQIBgAAAA==.',
Ew='Eww:BAEBNQAECn8UAAMMAAgKSxozVgBvAgAMAAgKIhozVgBvAgAQAAMK7xNmDQDrAAAAAA==.',
Fa='Falana:BAAANQABCggIDwAAAA==.',
Fe='Federica:BAAANQAECgEIAQAAAA==.Felladin:BAAANQAECgYIEQABNQAFFAcIEAADAOIVAA==.Felldeeds:BAACNQAFFH8QAAIDAAcK4hWOBADyAQADAAcK4hWOBADyAQA1AAQKfy4AAgMACgpAIXAKACEDAAMACgpAIXAKACEDAAAA.Fent:BAACNQAFFH8SAAIRAAYK1x4eCgDKAQARAAYK1x4eCgDKAQA1AAQKf0kAAhEACgrRIlcFAJwDABEACgrRIlcFAJwDAAAA.',
Fi='Fingerboppin:BAAANQAECgEIAwABNQAECgoKOwALAFYlAA==.Fingerr:BAAANQAECggIDQABNQAECgoKOwALAFYlAA==.Fingers:BAABNQAECn87AAILAAoKViWiAwBLAwALAAoKViWiAwBLAwAAAA==.Fitforakìng:BAABNQAECn8iAAIBAAkKVhanIQDWAQABAAkKVhanIQDWAQAAAA==.',
Fo='Foxxopally:BAAANQADCggIEAAAAA==.',
Fr='Freak:BAAANQADCgQIBAAAAA==.Froztbane:BAEANQAECgIIAgABNQAFFAcIFAASAA8VAA==.Froztbanshee:BAECNQAFFH8UAAISAAcKDxWsAwBoAQASAAcKDxWsAwBoAQA1AAQKf4cABBIACgqVJSQCAFcDABIACgqVJSQCAFcDABMACQpuF0IHABwCABQAAQqWD1eRADgAAAAA.',
Gi='Girthatbirth:BAABNQAECn8dAAIVAAoK2BO9JwAaAgAVAAoK2BO9JwAaAgABNQAECgoKMAAPAEweAA==.',
Gl='Glass:BAABNQAECn80AAIMAAoKBBn+PgBYAgAMAAoKBBn+PgBYAgAAAA==.',
Go='Goatsnake:BAAANQADCggICAAAAA==.Goth:BAAANQADCgQIBAAAAA==.',
Gr='Grimmadin:BAAANQADCgEJAQAAAA==.Grimmsaw:BAAANQAECgEJAQAAAA==.Grudge:BAAANQAECgYIDwABNQAECgoKHwAPAFYOAA==.Grudgetotem:BAABNQAECn8fAAIPAAoKVg5CTQCiAQAPAAoKVg5CTQCiAQAAAA==.',
Gu='Gullskull:BAAANQAECgQIBAAAAA==.',
Ha='Hanzoh:BAAANQAECgMIAwABNQAFFAIIBAAMAH8YAA==.Harrowhark:BAACNQAFFH8FAAIVAAIKnA8NGACBAAAVAAIKnA8NGACBAAA1AAQKfywAAxUACgoAHQMlAGsCABUACgoAHQMlAGsCABYABArIGTWZAM4AAAAA.Haveheart:BAAANQADCgQIAwABNQAECgkJIgABAFYWAA==.',
He='Herambae:BAAANQADCgEIAQAAAA==.Herculesàtan:BAAANQADCgEIAQAAAA==.Herculesátan:BAAANQADCgYIBgAAAA==.',
Ho='Honeyt:BAAANQAECgYICAAAAA==.',
Hu='Huntundra:BAABNQAECn8gAAMMAAoK4ATm2wD6AAAMAAgKXgXm2wD6AAAXAAYKbAHlaACJAAAAAA==.',
Hy='Hyacinth:BAABNQAECn9PAAIFAAoKUhcpGwAvAgAFAAoKUhcpGwAvAgAAAA==.',
Ia='Iamomegafox:BAACNQAFFH8KAAIYAAYKqA4IEADrAAAYAAYKqA4IEADrAAA1AAQKfzgAAxgACgpYIi0DABUDABgACQpYIi0DABUDABkABgqeCaMxADABAAAA.',
Ic='Icychill:BAAANQADCgUIBwAAAA==.',
Ig='Ignax:BAACNQAFFH8TAAIJAAYK3Qo9CgB1AQAJAAYK3Qo9CgB1AQA1AAQKfzYAAgkACgrfGP8SAH0CAAkACgrfGP8SAH0CAAAA.',
Il='Illidanstorm:BAAANQAECgEIAgAAAA==.',
Im='Imomeganisha:BAAANQADCggIEAABNQAFFAYICgAYAKgOAA==.',
In='Infoxxocated:BAAANQAECggIEAAAAA==.Innerhope:BAABNQAECn8yAAQaAAoKyyHmHQD5AgAaAAoKyyHmHQD5AgAbAAQKHQ6vTgDZAAAcAAQKpwe2FwC3AAAAAA==.Inspired:BAAANQAECgQIBAABNQAECgkJIgABAFYWAA==.',
Io='Ionias:BAABNQAECn8dAAQIAAkKXxkcmQCaAQAIAAcK0RccmQCaAQABAAMKGwn3WAB6AAAdAAMKBwXW4QBVAAAAAA==.',
Je='Jevik:BAAANQADCgEIAQAAAA==.',
Jo='Johadan:BAABNQAECn8ZAAIIAAkK9wRABwETAQAIAAkK9wRABwETAQAAAA==.Jonwane:BAABNQAECn8ZAAIOAAgK7Q1+HgATAQAOAAgK7Q1+HgATAQAAAA==.',
Ka='Kaelx:BAAANQADCgQIAgAAAA==.Kagnara:BAAANQADCgIJAgABNQAFFAIIBQAVAJwPAA==.',
Ke='Keely:BAAANQAECgQIDQAAAA==.',
Kh='Khalyia:BAAANQADCgYIDAAAAA==.',
Ki='Kiirabi:BAAANQADCggICAABNQAFFAkJHwADALUbAA==.Kirakitsune:BAAANQADCgcICAAAAA==.',
Kr='Krydunk:BAAANQADCgIIAgAAAA==.',
Ky='Kyle:BAAANQAECggIAQAAAA==.',
Li='Lione:BAAANQAECgQIBgAAAA==.',
Lo='Lorelei:BAAANQADCgMIAwAAAA==.',
Ly='Lyandra:BAAANQABCggIGAAAAA==.',
['Lì']='Lìllyanna:BAABNQAECn8vAAIBAAoKYxfgFgBFAgABAAoKYxfgFgBFAgAAAA==.',
Ma='Magmara:BAAANQADCgcJBwABNQAFFAIIBQAVAJwPAA==.Magustero:BAAANQAECgQIBgAAAA==.',
Me='Melithia:BAAANQADCgUIBQAAAA==.Meowhunter:BAAANQAECgUIAQAAAA==.',
Mi='Miami:BAABNQAECn8VAAMYAAcKSxYTJQAIAQAZAAUKvhatZgB3AQAYAAUK8hETJQAIAQABNQAFFAcIGAAeAHwaAA==.Miaraa:BAAANQAECgQIBgAAAA==.Mithos:BAAANQADCgYIBgAAAA==.',
Mu='Murgold:BAAANQAECgcICwAAAA==.',
My='Myssiadina:BAAANQABCgQIBwAAAA==.',
Na='Nayru:BAAANQAECgUIBgABNQAFFAIIBQAVAJwPAA==.',
Ne='Necrolyte:BAAANQAECgEIAQABNQAECgkJGAAKANMZAA==.Ned:BAEBNQAECn9FAAMfAAoK1iZxAACeAwAfAAoK1iZxAACeAwAgAAEKsSZ8JgB1AAABNQAFFAIIBgAaAI0mAA==.',
Ni='Ninax:BAABNQAECn8dAAIMAAkKZhk1SABAAgAMAAkKZhk1SABAAgAAAA==.',
No='Notcodus:BAAANQADCgUIBgAAAA==.',
Oc='Octomore:BAAANQAECgUIBQAAAA==.',
On='Onlydreams:BAAANQAECggIDwAAAA==.',
Pa='Pandamoniium:BAAANQAECggIEQABNQAECgoKRQAEAIQhAA==.Pandamonk:BAABNQAECn8xAAMhAAoKXiV6AAB3AwAhAAoKXiV6AAB3AwAiAAUKYgtQTgC9AAABNQAFFAUIEQALAFIlAA==.',
Pe='Percy:BAEANQADCgYICQAAAA==.',
Ph='Phoeníx:BAAANQADCgYIDAAAAA==.',
Pi='Picklejuice:BAAANQABCgIIAQAAAA==.Pickleswag:BAAANQAECgQIBAABNQAECgoKMAAPAEweAA==.',
Pl='Plagued:BAAANQADCgUIBQABNQAECgkJIgABAFYWAA==.',
Po='Powliden:BAAANQADCgIIBAAAAA==.',
Pr='Preservation:BAAANQAFFAIIAgAAAA==.',
Ps='Pseudonym:BAEBNQAECn8ZAAMLAAoKqhbhHAAWAgALAAoKqhbhHAAWAgAWAAMKSQedbQBlAAABNQAECgkJGgAdAG4UAA==.',
Pt='Ptulatha:BAAANQABCgEIAQAAAA==.',
Ra='Radagast:BAACNQAFFH8FAAIFAAIKNA1RHACHAAAFAAIKNA1RHACHAAA1AAQKfzIAAgUACgrPE3Q/AP8BAAUACgrPE3Q/AP8BAAAA.Radiantbug:BAABNQAECn8tAAIIAAoKIRjeWgAfAgAIAAoKIRjeWgAfAgAAAA==.Radicals:BAAANQAECgMIBAAAAA==.',
Re='Revna:BAAANQAECgQIBgAAAA==.',
Rh='Rhoem:BAABNQAECn81AAMLAAoK/BeFGQA3AgALAAoK/BeFGQA3AgAVAAQK0xOGfwCsAAAAAA==.',
Ri='Ripca:BAABNQAECn8kAAIDAAoKuB/IBQCMAwADAAoKuB/IBQCMAwABNQAFFAoKHgAdAAIcAA==.',
Ro='Rouge:BAAANQAECgIIAgABNQAFFAIIBAAMAH8YAA==.',
Sa='Sandster:BAAANQAECgcICQAAAA==.',
Sc='Scapeghost:BAAANQADCgYIBgAAAA==.',
Sh='Shalendris:BAAANQADCgcIBwAAAA==.Shalestrasz:BAAANQAECggICwAAAA==.Shochu:BAAANQAECgQIBgAAAA==.',
Sl='Slambiosis:BAEANQADCgEIAQABNQAECgkJGgAdAG4UAA==.',
Sn='Snuggle:BAAANQADCgUIBQAAAA==.',
Sp='Sp:BAACNQAFFH8XAAIaAAgK9AyuCQAfAgAaAAgK9AyuCQAfAgA1AAQKf04AAhoACgpVIhcHAIwDABoACgpVIhcHAIwDAAAA.Sparrow:BAAANQADCgIIAgABNQAECgoKNQAjABMPAA==.Sphene:BAAANQAECgIIAgAAAA==.',
St='Steelhi:BAAANQABCgIIAgAAAA==.Strongside:BAAANQADCgYIDAABNQAECgkJIgABAFYWAA==.',
Su='Sunshine:BAAANQAECgUIBQABNQAECgkJIgABAFYWAA==.',
Sw='Switchfoot:BAABNQAECn8XAAMkAAcK+BhcDACSAQAYAAcKdBXjRQCvAQAkAAYKfBdcDACSAQAAAA==.',
Sy='Syleria:BAAANQAECgUICwAAAA==.',
Ta='Tale:BAECNQAFFH8KAAIPAAQKMwoyFgC9AAAPAAQKMwoyFgC9AAA1AAQKf04AAg8ACgqLHfUmAOcCAA8ACgqLHfUmAOcCAAE1AAQKCAgUAAwASxoA.Tankard:BAAANQADCggICQABNQAECgkJIgABAFYWAA==.',
To='Toyotaavalon:BAAANQADCgYICAABNQAECgoKMAAPAEweAA==.Toyotacamry:BAABNQAECn8wAAMPAAoKTB4yPQCBAgAPAAoK/xwyPQCBAgAlAAcKKhyrFQAOAgAAAA==.Toyotatundra:BAAANQAECgQIBgABNQAECgoKMAAPAEweAA==.',
Up='Upliftw:BAAANQADCggICAAAAA==.',
Va='Vamana:BAAANQAECgEIAgABNQAFFAIIBAAMAH8YAA==.',
Ve='Velf:BAABNQAECn8WAAISAAoKLBY5IQCVAQASAAoKLBY5IQCVAQABNQAECgoKPAAIAJkiAA==.Velzard:BAAANQABCgEIAQAAAA==.',
Vi='Violash:BAABNQAECn8iAAIeAAoKbCOMAgCLAwAeAAoKbCOMAgCLAwAAAA==.',
['Vö']='Vöre:BAAANQADCgEJAQAAAA==.',
Wh='Whitessin:BAAANQADCgcICAAAAA==.Whýý:BAAANQADCggIFAAAAA==.',
Wi='Wireless:BAAANQABCgYIDAAAAA==.',
Yo='Yofoxxo:BAACNQAFFH8UAAIdAAgK7BMfBABIAgAdAAgK7BMfBABIAgA1AAQKfzcAAh0ACgp3JLYKAHgDAB0ACgp3JLYKAHgDAAAA.',
Ys='Ysayle:BAAANQADCgMIAwAAAA==.',
Za='Zakariahh:BAAANQADCgYIBgAAAA==.Zarea:BAABNQAECn8cAAMIAAgKOxoSfgAuAgAIAAgKAxYSfgAuAgABAAQKJh9COAApAQAAAA==.Zarlon:BAABNQAECn8bAAIIAAoKfh6TJwDDAgAIAAoKfh6TJwDDAgABNQAFFAIIBAAMAH8YAA==.',
Ze='Zengriff:BAABNQAECn8lAAIhAAcKdyRkBQBLAgAhAAcKdyRkBQBLAgAAAA==.Zerena:BAAANQAECgEIAQAAAA==.',
Zu='Zucarithas:BAABNQAECn8yAAMdAAoKvQ6eSgDpAQAdAAoKvQ6eSgDpAQAIAAMKZwiecAFXAAAAAA==.',
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
