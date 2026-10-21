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

local lookup = {'Paladin-Protection','Unknown-Unknown','Mage-Arcane','Druid-Balance','Mage-Frost','Mage-Fire','Paladin-Retribution','Evoker-Preservation','Warlock-Demonology','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','Druid-Feral','Shaman-Elemental','Hunter-Survival','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Holy','Evoker-Devastation','Warrior-Arms','Warlock-Affliction','Rogue-Outlaw','Shaman-Enhancement','Monk-Brewmaster',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abjured:BAAANQABCgIIAgABNQAECgcIGwABABYXAA==.Absolu:BAAANQABCgcICQAAAA==.',
An='Anaibubble:BAAANQADCggICQAAAA==.',
Ar='Ariadné:BAAANQAECgcIEwAAAA==.Arialla:BAAANQAECgUICgABNQABCgQICAACAAAAAA==.',
Az='Azalan:BAAANQADCgUIBQABNQAECggIDgACAAAAAA==.',
Ba='Bandiaz:BAABNQAECn8WAAIDAAYKPhQ+fQDFAAADAAYKPhQ+fQDFAAAAAA==.Banson:BAAANQAECgIIAgAAAA==.',
Be='Bearlover:BAAANQAECgQIBgAAAA==.Bellatrixx:BAABNQAECn8YAAIEAAYKaASSMQCYAAAEAAYKaASSMQCYAAAAAA==.',
Bl='Blighted:BAAANQADCgYIBgABNQAECgcIGwABABYXAA==.',
Bo='Bootles:BAABNQAECn8VAAQFAAgKuBnZDwCqAQADAAYKFxIR6gC2AQAFAAYKcRXZDwCqAQAGAAIK7B6nBwC5AAAAAA==.Bowl:BAAANQADCgYIEQAAAA==.',
Bu='Bullwings:BAABNQAECn8mAAIHAAkKHCJFJwApAwAHAAkKHCJFJwApAwAAAA==.Burnin:BAABNQAECn8XAAIIAAgKGQ/IHwDYAQAIAAgKGQ/IHwDYAQAAAA==.',
Ch='Charrend:BAABNQAECn8aAAIBAAgKPwLATAC2AAABAAgKPwLATAC2AAAAAA==.',
Co='Cobalt:BAECNQAFFH8JAAIJAAUKmRKXCADkAAAJAAUKmRKXCADkAAA1AAQKfzEAAgkACQoJItcXACkDAAkACQoJItcXACkDAAAA.Coco:BAAANQADCggICAABNQAECggIDgACAAAAAA==.Codus:BAAANQAECgUICQAAAA==.',
Cr='Crazon:BAAANQADCgYIEQAAAA==.',
Ct='Cthulhu:BAAANQAECggIDwAAAA==.',
Da='Damndalion:BAAANQABCgQIBAAAAA==.Darkdworf:BAACNQAFFH8RAAIKAAUKUiWEAgB2AQAKAAUKUiWEAgB2AQA1AAQKfy8AAgoACgpMJaUHAIEDAAoACgpMJaUHAIEDAAAA.Darner:BAAANQADCggIEQAAAA==.',
De='Debuff:BAAANQAECgQIBQABNQAECgoKMQALANcgAA==.',
Do='Doomradicals:BAAANQAECgUIDAAAAA==.Doriian:BAAANQADCggIEQAAAA==.',
Dr='Dragothu:BAAANQAECgIIAwABNQAECgkJJgAHABwiAA==.Druidbelly:BAABNQAECn8pAAMMAAgKQR7+AgAOAgAMAAgKQR7+AgAOAgANAAEKQAhnSQAnAAAAAA==.',
Du='Dushlan:BAABNQAECn8WAAIOAAcKvghlnQBcAQAOAAcKvghlnQBcAQAAAA==.Dutton:BAAANQABCggIFAAAAA==.',
Ea='Eatsbabies:BAAANQAECgMIAwAAAA==.',
Ei='Eiskält:BAAANQAECgIIAgAAAA==.',
En='Endrin:BAAANQAECgQIBgAAAA==.',
Ew='Eww:BAEBNQAECn8UAAMLAAgKSxozVgBvAgALAAgKIhozVgBvAgAPAAMK7xNmDQDrAAAAAA==.',
Fe='Fedelia:BAAANQADCgYIDAAAAA==.Federica:BAAANQAECgEIAQAAAA==.Felladin:BAAANQAECgYIEAABNQAFFAUIDgAQAKYZAA==.Felldeeds:BAACNQAFFH8OAAIQAAUKphlMAgCOAQAQAAUKphlMAgCOAQA1AAQKfyYAAhAACgpAIXAKACEDABAACgpAIXAKACEDAAAA.Fent:BAACNQAFFH8RAAIRAAUKlh4ABACPAQARAAUKlh4ABACPAQA1AAQKfzAAAhEACgqaIlcFAJwDABEACgqaIlcFAJwDAAAA.',
Fi='Fingerboppin:BAAANQAECgEIAQABNQAECgoKJgAKAIcjAA==.Fingerr:BAAANQADCgUIBQABNQAECgoKJgAKAIcjAA==.Fingers:BAABNQAECn8mAAIKAAoKhyP0AwAjAgAKAAoKhyP0AwAjAgAAAA==.Fitforakìng:BAABNQAECn8bAAIBAAcKFhenIQDWAQABAAcKFhenIQDWAQAAAA==.',
Fo='Foxxopally:BAAANQADCggIEAAAAA==.',
Fr='Froztbane:BAEANQAECgIIAgABNQAFFAYIEgASAJ8WAA==.Froztbanshee:BAECNQAFFH8SAAISAAYKnxZ1AQBKAQASAAYKnxZ1AQBKAQA1AAQKf1cAAxIACgrdI7oDAJwDABIACgrdI7oDAJwDABMAAQqWD1eRADgAAAAA.',
Gl='Glass:BAABNQAECn8XAAILAAkKLBjaWgBkAgALAAkKLBjaWgBkAgAAAA==.',
Go='Goatsnake:BAAANQADCggICAAAAA==.Goth:BAAANQADCgQIBAAAAA==.',
Gr='Grimmadin:BAAANQADCgEJAQAAAA==.Grimmsaw:BAAANQAECgEJAQAAAA==.Grudge:BAAANQAECgYIDwABNQAECgkJFgAOANYNAA==.Grudgetotem:BAABNQAECn8WAAIOAAkK1g0BJQAoAQAOAAkK1g0BJQAoAQAAAA==.',
Gu='Gullskull:BAAANQADCggIEwAAAA==.',
Ha='Hanzoh:BAAANQADCgIIAgABNQAECgoKMQALANcgAA==.Harrowhark:BAABNQAECn8gAAMUAAoKchkDJQBrAgAUAAoKchkDJQBrAgAVAAQKyBk1mQDOAAAAAA==.Haveheart:BAAANQADCgIIAQABNQAECgcIGwABABYXAA==.',
He='Herambae:BAAANQADCgEIAQAAAA==.Herculesàtan:BAAANQADCgEIAQAAAA==.Herculesátan:BAAANQADCgYIBgAAAA==.',
Ho='Honeyt:BAAANQAECgYICAAAAA==.',
Hu='Huntundra:BAAANQAECgcIEAAAAA==.',
Hy='Hyacinth:BAABNQAECn8xAAIEAAoKLhLrBQDgAQAEAAoKLhLrBQDgAQAAAA==.',
Ia='Iamomegafox:BAACNQAFFH8IAAIWAAQKhxAIEADrAAAWAAQKhxAIEADrAAA1AAQKfyoAAxYACgqyHmoJAIgBABYACQqyHmoJAIgBABcABgqeCaMxADABAAAA.',
Ic='Icychill:BAAANQADCgUIBwAAAA==.',
Ig='Ignax:BAACNQAFFH8PAAIIAAUKQQjOBAAwAQAIAAUKQQjOBAAwAQA1AAQKfzEAAggACgrfGP8SAH0CAAgACgrfGP8SAH0CAAAA.',
Im='Imomeganisha:BAAANQADCggIEAABNQAFFAQICAAWAIcQAA==.',
In='Infoxxocated:BAAANQAECggIEAAAAA==.Innerhope:BAABNQAECn8oAAQYAAoKHiHmHQD5AgAYAAoKHiHmHQD5AgAZAAQKHQ6vTgDZAAAaAAQKpwe2FwC3AAAAAA==.Inspired:BAAANQAECgMIAgABNQAECgcIGwABABYXAA==.',
Io='Ionias:BAABNQAECn8UAAQHAAcKeA+U5ABSAQAHAAcKeA+U5ABSAQABAAMKGwn3WAB6AAAbAAEKeAOcKQEsAAAAAA==.',
Je='Jevik:BAAANQADCgEIAQAAAA==.',
Jo='Johadan:BAABNQAECn8XAAIHAAcKFQRABwETAQAHAAcKFQRABwETAQAAAA==.Jonwane:BAAANQAECgUIDgAAAA==.',
Ka='Kaelx:BAAANQADCgIIAgAAAA==.Kagnara:BAAANQADCgIJAgABNQAECgoKIAAUAHIZAA==.',
Ke='Keely:BAAANQAECgMIBAAAAA==.',
Kh='Khalyia:BAAANQADCgYIDAAAAA==.',
Ki='Kiirabi:BAAANQADCggICAABNQAFFAgIFQAQAJAaAA==.Kirakitsune:BAAANQADCgcICAAAAA==.',
Ky='Kyle:BAAANQAECggIAQAAAA==.',
Li='Lione:BAAANQAECgQIBgAAAA==.',
Lo='Lorelei:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllyanna:BAABNQAECn8iAAIBAAgKGBrgFgBFAgABAAgKGBrgFgBFAgAAAA==.',
Ma='Magmara:BAAANQADCgcJBwABNQAECgoKIAAUAHIZAA==.Magustero:BAAANQAECgQIAwAAAA==.',
Me='Melithia:BAAANQADCgUIBQAAAA==.Meowhunter:BAAANQAECgQIAQAAAA==.',
Mi='Miami:BAAANQAECgMIBAABNQAFFAcIFwAcAHwaAA==.Miaraa:BAAANQAECgQIBgAAAA==.Mithos:BAAANQADCgYIBgAAAA==.',
Mu='Murgold:BAAANQAECgcICwAAAA==.',
My='Myssiadina:BAAANQABCgQIBwAAAA==.',
Na='Nayru:BAAANQAECgUIBgABNQAECgoKIAAUAHIZAA==.',
Ne='Necrolyte:BAAANQAECgEIAQABNQAECggIDwACAAAAAA==.Ned:BAABNQAECn8oAAIdAAoKfibhAAACBAAdAAoKfibhAAACBAABNQAFFAIIBgAYAI0mAA==.',
Ni='Ninax:BAABNQAECn8VAAILAAcKexmaFQDIAQALAAcKexmaFQDIAQAAAA==.',
No='Notcodus:BAAANQADCgUIBQAAAA==.',
Oc='Octomore:BAAANQAECgUIBQAAAA==.',
Pa='Pandamoniium:BAAANQAECgQIBwABNQAECgoKNwADAHsfAA==.Pandamonk:BAAANQAECgYICwABNQAFFAUIEQAKAFIlAA==.',
Pe='Percy:BAEANQADCgcICQAAAA==.',
Ph='Phoeníx:BAAANQADCgYIDAAAAA==.',
Pi='Picklejuice:BAAANQABCgIIAQAAAA==.Pickleswag:BAAANQAECgQIBAABNQAECgoKLQAOAFMdAA==.',
Po='Powliden:BAAANQADCgIIBAAAAA==.',
Pr='Preservation:BAAANQAFFAIIAgAAAA==.',
Ps='Pseudonym:BAEANQAECgQIBQABNQAECgkJFgAbADoUAA==.',
Pt='Ptulatha:BAAANQABCgEIAQAAAA==.',
Ra='Radagast:BAABNQAECn8mAAIEAAoKhw50PwD/AQAEAAoKhw50PwD/AQAAAA==.Radiantbug:BAABNQAECn8gAAIHAAoKjBdOCwAsAgAHAAoKjBdOCwAsAgAAAA==.Radicals:BAAANQAECgMIAwAAAA==.',
Re='Revna:BAAANQAECgQIBgAAAA==.',
Rh='Rhoem:BAABNQAECn8WAAMKAAkKcw/eTgC6AQAKAAkK9w3eTgC6AQAUAAQK0xOGfwCsAAAAAA==.',
Ri='Ripca:BAAANQAECgQIBAABNQAECggIFQAIAJwiAA==.',
Ro='Rouge:BAAANQAECgIIAgABNQAECgoKMQALANcgAA==.',
Sa='Sandster:BAAANQAECgcICQAAAA==.',
Sc='Scapeghost:BAAANQADCgYIBgAAAA==.',
Sh='Shalendris:BAAANQADCgcIBwAAAA==.Shalestrasz:BAAANQAECggICwAAAA==.Shochu:BAAANQAECgQIBgAAAA==.',
Sl='Slambiosis:BAEANQADCgEIAQABNQAECgkJFgAbADoUAA==.',
Sn='Snuggle:BAAANQADCgUIBQAAAA==.',
Sp='Sp:BAACNQAFFH8SAAIYAAYKoA6xCABCAQAYAAYKoA6xCABCAQA1AAQKfzEAAhgACgpNIhcHAIwDABgACgpNIhcHAIwDAAAA.Sparrow:BAAANQADCgIIAgABNQAECgoKIwAeAJMLAA==.Sphene:BAAANQAECgEIAQAAAA==.',
St='Steelhi:BAAANQABCgIIAgAAAA==.Strongside:BAAANQADCgYICwABNQAECgcIGwABABYXAA==.',
Su='Sunshine:BAAANQADCgYIBgABNQAECgcIGwABABYXAA==.',
Sw='Switchfoot:BAABNQAECn8XAAMfAAcK+BhcDACSAQAWAAcKdBXjRQCvAQAfAAYKfBdcDACSAQAAAA==.',
Sy='Syleria:BAAANQADCggICAAAAA==.',
Ta='Tale:BAEBNQAECn9CAAIOAAoKRBr1JgDnAgAOAAoKRBr1JgDnAgABNQAECggIFAALAEsaAA==.',
To='Toyotaavalon:BAAANQADCgYICAABNQAECgoKLQAOAFMdAA==.Toyotacamry:BAABNQAECn8tAAMOAAoKUx3lAwBMAgAOAAoKBxzlAwBMAgAgAAcKKhyrFQAOAgAAAA==.Toyotatundra:BAAANQAECgQIBgABNQAECgoKLQAOAFMdAA==.',
Up='Upliftw:BAAANQADCggICAAAAA==.',
Va='Vamana:BAAANQAECgEIAgABNQAECgoKMQALANcgAA==.',
Ve='Velf:BAAANQAECgUIBgABNQAECgkJJgAHABwiAA==.Velzard:BAAANQABCgEIAQAAAA==.',
Vi='Violash:BAABNQAECn8iAAIcAAoKbCOMAgCLAwAcAAoKbCOMAgCLAwAAAA==.',
['Vö']='Vöre:BAAANQADCgEJAQAAAA==.',
Wh='Whitessin:BAAANQADCgcICAAAAA==.Whýý:BAAANQADCggIFAAAAA==.',
Yo='Yofoxxo:BAACNQAFFH8SAAIbAAcK/BQfBABIAgAbAAcK/BQfBABIAgA1AAQKfygAAhsACgojItUQAEYDABsACgojItUQAEYDAAAA.',
Ys='Ysayle:BAAANQADCgMIAwAAAA==.',
Za='Zakariahh:BAAANQADCgYIBgAAAA==.Zarea:BAABNQAECn8VAAMHAAgKOxoSfgAuAgAHAAgKAxYSfgAuAgABAAQKJh9COAApAQAAAA==.Zarlon:BAAANQAECgcICQABNQAECgoKMQALANcgAA==.',
Ze='Zengriff:BAABNQAECn8eAAIhAAcKviPIAABmAgAhAAcKviPIAABmAgAAAA==.Zerena:BAAANQAECgEIAQAAAA==.',
Zu='Zucarithas:BAABNQAECn8fAAMbAAoKaw/8KwAyAQAbAAkKJg78KwAyAQAHAAIKmgmhfgFbAAAAAA==.',
['År']='Årthás:BAAANQADCgUICgAAAA==.',
['Æl']='Ælyse:BAAANQADCggICAAAAA==.',
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
