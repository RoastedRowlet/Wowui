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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Mage-Arcane','Druid-Balance','Hunter-Survival','Paladin-Retribution','Monk-Brewmaster','Monk-Mistweaver','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','Priest-Shadow','Rogue-Subtlety','Druid-Guardian','Paladin-Holy','Warlock-Affliction','Druid-Feral','Monk-Windwalker','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Frost','Paladin-Protection','DemonHunter-Vengeance','Priest-Holy','Evoker-Preservation','Evoker-Devastation','Druid-Restoration',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarix:BAAANQAECgYIEgAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAAANQAECgYIDwAAAA==.',
Ag='Agkistrodon:BAAANQADCgUIBQABNQAECgYIEgABAAAAAA==.',
Ai='Aicaramba:BAAANQAECgcICgAAAA==.Aileen:BAAANQAECgQIBAAAAA==.',
Aj='Ajay:BAAANQAECgQIBAAAAA==.',
Ak='Akashi:BAAANQAECgYICQABNQAECgkJKQACAPsdAA==.',
Al='Alacrodie:BAAANQADCgUIDQAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgUIDAABAAAAAA==.',
An='Angrytotems:BAAANQAECgQJBAABNQAECgcIEAABAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgQIBQABNQAECgYICgABAAAAAA==.',
Ar='Aragorno:BAAANQAECgMIBgAAAA==.Arcturen:BAAANQAECgIIAgAAAA==.Ardala:BAAANQABCgIIAgAAAA==.Arenthal:BAAANQAECgQICAABNQAECggIIwADAMQdAA==.Arturaan:BAAANQABCggIEgAAAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgYICwABAAAAAA==.Ashiera:BAAANQAECgYIEQAAAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgEIAgAAAA==.',
Au='Aurorée:BAAANQAECgQIBAAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgUIDQAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAABNQAECoEcAAIEAAgKdhT4LQApAgAEAAgKdhT4LQApAgAAAA==.',
Be='Beeboop:BAAANQABCgYIEAAAAA==.Belly:BAABNQAECoEbAAIFAAgKgRb5AwBwAgAFAAgKgRb5AwBwAgAAAA==.Belrae:BAAANQADCggIDQAAAA==.Benchfresh:BAABNQAECoEUAAIGAAcKORzFVwA8AgAGAAcKORzFVwA8AgAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQAECgEIAQAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBgAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQADCgYIBgAAAA==.',
Bl='Bloodarrow:BAAANQADCgUIBwAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQIBQAAAA==.Bonanas:BAAANQABCggIBwAAAA==.Bonegavel:BAAANQABCgQIBgAAAA==.Bookhuntress:BAAANQAECgYIBgAAAA==.',
Br='Branex:BAAANQADCggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAABNQAECoEaAAIHAAcKGhr/CwAEAgAHAAcKGhr/CwAEAgAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECoEfAAIIAAgKxA5fGAChAQAIAAgKxA5fGAChAQAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgcICwAAAA==.Bronad:BAACNQAFFIEIAAMJAAQKSCC4AgDAAAADAAMKRR/CHQAaAQAJAAIKzR+4AgDAAAA1AAQKgTQAAwMACQrGJoEAAAIEAAMACQrGJoEAAAIEAAkAAQo/HzAzAEMAAAAA.Broomhandle:BAAANQAECgUIDgAAAA==.',
Bu='Bumbushka:BAAANQAECgYICgAAAA==.Burinn:BAAANQAECgIIAgABNQAECgYIEgABAAAAAA==.',
Ca='Caeus:BAAANQAECgUICgAAAA==.Cam:BAAANQAECgYIEQAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgUICgAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBgAAAA==.Chelan:BAAANQAECgYIEgAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQABCgYJCwAAAA==.Chuye:BAAANQAECgEJAQABNQAECgcIEQABAAAAAA==.',
Cl='Clambulance:BAABNQAECoEhAAIKAAgKnhibPABuAgAKAAgKnhibPABuAgAAAA==.',
Cn='Cnova:BAAANQAECgUICQAAAA==.',
Co='Codythedead:BAACNQAFFIEIAAMLAAQKmxerCAAKAQALAAMKLx+rCAAKAQAMAAEK3wDLLwAQAAA1AAQKgSQAAgsACQrFITkQAAcDAAsACQrFITkQAAcDAAAA.Coraf:BAACNQAFFIEIAAINAAQKRCC0BwCNAQANAAQKRCC0BwCNAQA1AAQKgSAAAg0ACQqFIXgNADEDAA0ACQqFIXgNADEDAAAA.Coyotl:BAAANQAECgYIBgAAAA==.',
Cr='Crazyazshamy:BAAANQADCgYIBgAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Danak:BAAANQADCgQICQAAAA==.',
De='Deadlyfrosty:BAAANQADCgUICAAAAA==.Deathmob:BAAANQAECgUIDQAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECgQICQABAAAAAA==.Debixie:BAABNQAECoEeAAMCAAkKlxy9CgACAwACAAkKlxy9CgACAwAOAAYKuBOxCwB2AQAAAA==.Decisive:BAAANQADCgYIBgABNQAFFAcIEgAPALEfAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgYICAAAAA==.Demiurge:BAAANQAECgYIDgAAAA==.',
Di='Diasundra:BAABNQAECoEbAAIKAAgKhiG1GQABAwAKAAgKhiG1GQABAwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECgIIAgABNQAECgYICQABAAAAAA==.Dottingyou:BAACNQAFFIEIAAMQAAQKzw/KDQCUAAAPAAIKNBrnHACoAAAQAAIKagXKDQCUAAA1AAQKgSEAAxAACQqsH4MUAL4BAA8ABwphH+xBAEwCABAABgoiGoMUAL4BAAAA.',
Dr='Dracthyrbm:BAAANQADCgYJFAAAAA==.Dreepy:BAAANQAECgUJBQAAAA==.Drransom:BAAANQADCgQIBQAAAA==.Dryan:BAAANQAECgYICwAAAA==.',
Du='Duo:BAABNQAECoEaAAIKAAcKQBQNZgDyAQAKAAcKQBQNZgDyAQAAAA==.Duragon:BAAANQAECgYIEgAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Elciere:BAAANQADCggIDQAAAA==.Eloreith:BAAANQAECggIEgAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAAANQAECgUIEwAAAA==.',
En='Endressa:BAABNQAECoEfAAMRAAgKRBB9BgDrAQARAAgKRBB9BgDrAQASAAIKIhYKSgCUAAAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAAANQAECgYICgAAAA==.',
Es='Eski:BAABNQAECoEhAAMOAAgKwB4mAwDbAgAOAAgKwB4mAwDbAgACAAIK2wkmagBjAAAAAA==.Essaena:BAAANQAECgYIEQAAAA==.',
Eu='Eura:BAAANQADCgEJAQAAAA==.Eureka:BAEANQAECgYIEAAAAA==.',
Fa='Faddeyshnek:BAABNQAECoEaAAIKAAcKawtYggCmAQAKAAcKawtYggCmAQAAAA==.Farmeador:BAAANQAECgEIAQAAAA==.Fatgirljuice:BAAANQAFFAMIAwAAAA==.',
Fe='Felysambre:BAAANQAECgMIBAAAAA==.',
Fi='Fish:BAACNQAFFIEVAAISAAcKXiSLAAC9AgASAAcKXiSLAAC9AgA1AAQKgScAAhIACQrjJj4AAP0DABIACQrjJj4AAP0DAAAA.',
Fl='Flight:BAABNQAECoEpAAMCAAkK+x2TEwCXAgACAAgKVR2TEwCXAgATAAYKXBa1HADIAQAAAA==.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQABCgUIBgAAAA==.Forsynth:BAAANQAECgQICQAAAA==.',
Fu='Fubar:BAAANQADCggIDgAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQIBgAAAA==.',
Gl='Glinda:BAAANQADCgUIBQAAAA==.',
Go='Gonjah:BAAANQAECgQIBQAAAA==.',
Gr='Grabomage:BAAANQAECgQICAABNQAFFAQICAAJAEggAA==.Grabovoker:BAAANQADCgIIAgABNQAFFAQICAAJAEggAA==.Grazienne:BAAANQADCgUIDAAAAA==.Greavos:BAAANQAECgYIDwAAAA==.Griggus:BAAANQAECgYICQAAAA==.Grimgar:BAAANQAECgYIDwAAAA==.Grimmshady:BAAANQADCgQIBgAAAA==.Grumpsky:BAAANQADCgEIAQABNQAECgYIDwABAAAAAA==.',
Gu='Gumbles:BAAANQAECgcIEQAAAA==.Gurney:BAAANQAECgcIEAAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgIIAgAAAA==.',
Ha='Hanekawa:BAAANQAECgYIDQABNQAECgkJJQAJAL0kAA==.Hannie:BAAANQADCgUICwAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAAANQAECgYIDgAAAA==.Heatseeka:BAAANQAECgYIEwAAAA==.Hexxiz:BAAANQAECgQIBQABNQAECgcIFwAUAMAiAA==.',
Hi='Hiphopinator:BAAANQAECgUIDgAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECoEiAAIVAAgKVhq+MQBjAgAVAAgKVhq+MQBjAgAAAA==.Holyterror:BAAANQADCgUIDQAAAA==.',
Ia='Ianthe:BAAANQAECgIIAgAAAA==.',
Ib='Iboga:BAAANQAECgQIDgAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgUICAAAAA==.',
Il='Illumona:BAAANQAECgMIBQAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgQICgAAAA==.Intrépidice:BAAANQAECgMICAAAAA==.',
Ix='Ixtabay:BAABNQAECoEmAAQWAAkKox7wAQDnAgAWAAkKgBzwAQDnAgAQAAMK3BfvNQDVAAAPAAMKvQ3s2ACvAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIBgAAAA==.Jaylinn:BAABNQAECoEaAAIKAAcKigd8kwB7AQAKAAcKigd8kwB7AQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAABNQAECoEVAAIKAAcKJxbnVgAcAgAKAAcKJxbnVgAcAgABNQAECggIIQAOAMAeAA==.Jellykins:BAAANQAECgYICwAAAA==.',
Ji='Jimjamjuju:BAAANQAECgUICQAAAA==.Jimsonweed:BAAANQAECgUIDAAAAA==.',
Jo='Josie:BAAANQAECgYIDQAAAA==.Jozbirt:BAABNQAECoEeAAIXAAgKUA4NDQDeAQAXAAgKUA4NDQDeAQAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgUICgAAAA==.Kalaanri:BAAANQAECgIIAgAAAA==.Kalyandra:BAAANQAECgQICAAAAA==.Karlach:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.Karumie:BAABNQAECoEZAAINAAgKohIeUQDPAQANAAgKohIeUQDPAQAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgUIBwAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAAANQAECgYIDgAAAA==.',
Kh='Kheyra:BAAANQAECgYIEgAAAA==.',
Ki='Kirsha:BAAANQADCggIEAABNQAECgIIBgABAAAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMJBAAAAA==.',
Ko='Kohnor:BAAANQADCgQIDAAAAA==.Koopalizard:BAAANQAECgUIDAAAAA==.Kopi:BAAANQAECgYICgAAAA==.Korlatt:BAAANQAECgYICwAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAAANQAECgYIEgAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgQICwAAAA==.',
La='Labella:BAAANQADCgQIBAAAAA==.Lacia:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.Laih:BAAANQAECgUIBgAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAAANQAECgYIDwAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYICQAAAA==.Liirah:BAAANQADCgMIAwAAAA==.Lilyfox:BAAANQAECgQIBgAAAA==.Lindithrial:BAAANQABCgQIBAAAAA==.Livingdead:BAAANQADCggIHwAAAA==.',
Lo='Lorianne:BAAANQADCggJEAAAAA==.Lorraine:BAAANQADCgQIBAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJJgAWAKMeAA==.Madalyn:BAAANQADCgEIAQAAAA==.Magdelyne:BAAANQAECggIAQAAAA==.Makklehaney:BAAANQAECgUIDQAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAAANQAECgUIDQAAAA==.Matthad:BAAANQAECgUICgAAAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAAANQAECgYIEAAAAA==.',
Mi='Milyyanna:BAAANQADCgUIDAAAAA==.Mirilla:BAAANQAECgYIDAAAAA==.',
Mo='Moddoxx:BAAANQAECgUICgAAAA==.Mohawk:BAAANQAECgMIBQAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgABNQAFFAMIAwABAAAAAA==.Monkle:BAABNQAECoEZAAIYAAgKqB6jDgC9AgAYAAgKqB6jDgC9AgAAAA==.Monohan:BAAANQADCgUIBQABNQAECgUIDQABAAAAAA==.Moonsii:BAAANQAECgUIDAAAAA==.Mooroth:BAAANQAECgYIEAAAAA==.Morkilro:BAAANQABCgIJAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Ms='Msasani:BAAANQADCgEIAQABNQAECgYIEgABAAAAAA==.',
Mu='Muddler:BAAANQAECgIIAgAAAA==.Murinn:BAAANQAECgUIDgAAAA==.',
['Mà']='Màggles:BAAANQAECgUICAAAAA==.',
Na='Nadd:BAAANQAECgMIBQAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECoEeAAMZAAgK9RagDABpAgAZAAgKTxagDABpAgAaAAUKwRGYiQA0AQAAAA==.',
Ne='Negrido:BAABNQAECoEaAAQPAAcKZCDNTQAkAgAPAAYKuB7NTQAkAgAQAAMKDRsHMQDtAAAWAAIKHxtzFQCoAAAAAA==.Nei:BAAANQAECgYIDwAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQAECgMIBQAAAA==.',
No='Noelle:BAAANQAECgUICAAAAA==.Norelei:BAAANQADCgQIBgABNQAECgYIEgABAAAAAA==.Noriyuki:BAAANQAECgMICAAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgQIBAAAAA==.',
Ol='Olderon:BAAANQAECgUICgAAAA==.Olrong:BAAANQAECgYIDwAAAA==.Oluja:BAAANQAECgQICgAAAA==.',
On='Onuris:BAAANQAECgEIAQAAAA==.',
Op='Opacuslupus:BAAANQAECgQIBQAAAA==.Oppressin:BAAANQAECgUIDQAAAA==.',
Os='Oshunn:BAABNQAECoEcAAIDAAgK/RA4pwDqAQADAAgK/RA4pwDqAQAAAA==.Oshìe:BAABNQAECoEeAAIVAAgKfSDbFwDwAgAVAAgKfSDbFwDwAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAABNQAECoEaAAMLAAcKpx3PLgAbAgALAAcKpx3PLgAbAgAbAAUK4hGIQwA5AQAAAA==.Ovscur:BAABNQAECoEWAAMPAAYK7B7egQCBAQAPAAQKhyHegQCBAQAQAAIKthm7RQCaAAAAAA==.',
Pa='Paladinjohn:BAACNQAFFIEHAAIGAAQKqSFtBgCTAQAGAAQKqSFtBgCTAQA1AAQKgSMAAgYACQrUJXcIAKMDAAYACQrUJXcIAKMDAAAA.Palykat:BAAANQAECgIIAgAAAA==.Papiroflz:BAABNQAECoEaAAMaAAgKYB9AHgDjAgAaAAgKYB9AHgDjAgANAAMKMxbXsQCyAAAAAA==.',
Pe='Pennywisé:BAAANQAECgcIEwAAAA==.Pesttilence:BAAANQABCgYIDAAAAA==.',
Pl='Plaguegying:BAAANQAECgQICQABNQAECgIIAgABAAAAAA==.Ploofee:BAAANQAECgMIAwAAAA==.',
Pr='Progresz:BAAANQAECgEIAQAAAA==.',
Pu='Purebread:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAABNQAECoEZAAIEAAcKgQYdVAA4AQAEAAcKgQYdVAA4AQAAAA==.',
Qa='Qaren:BAAANQADCgUICgAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAABNQAECoEaAAIXAAcK6x4hCAByAgAXAAcK6x4hCAByAgAAAA==.Rannï:BAAANQADCgQIBAABNQAECgkJJgAWAKMeAA==.Raskreia:BAAANQAECgYICAABNQAECgkJJQAJAL0kAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQADCgcIDAAAAA==.',
Re='Reeven:BAAANQAECgcIFQAAAQ==.Revokely:BAAANQAECgYIDgAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAFFAQICAAJAEggAA==.Rhetegast:BAABNQAECoEcAAIcAAgKgBQdGADgAQAcAAgKgBQdGADgAQAAAA==.',
Ri='Rieloesh:BAAANQADCgYIBgAAAA==.Rike:BAAANQAECgYIDwAAAA==.Ristretto:BAAANQADCgUJBQABNQAECgYICgABAAAAAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAAANQAECgYIDwAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAAANQAECgYIDQAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgIJAgABNQAECgcIHQAdABIcAA==.',
Sa='Salandria:BAABNQAECoEYAAQcAAgKWRg0FAASAgAcAAgK3xc0FAASAgAVAAUKSSStRgAJAgAGAAEKZhWORQE3AAAAAA==.Sarionian:BAAANQAECgMIBQAAAA==.Sarjin:BAAANQADCgYIBgABNQAECgYIEgABAAAAAA==.Sarvinblue:BAABNQAECoEkAAMNAAkKMR+jDQAvAwANAAkKMR+jDQAvAwAaAAYK/BFScAB6AQAAAA==.',
Sc='Scopolamine:BAAANQAECgQIBQAAAA==.',
Se='Sevrin:BAABNQAECoEaAAIMAAcKRhSRQQC0AQAMAAcKRhSRQQC0AQAAAA==.Seymonty:BAABNQAECoEaAAMRAAcKNRD2CgBhAQARAAYKWhD2CgBhAQAeAAcKWweNdQBMAQAAAA==.',
Sh='Shaeko:BAAANQADCggIEgAAAA==.Shanir:BAAANQADCgIJAgAAAA==.Shazlulu:BAAANQAECgIIAgAAAA==.Shaznoir:BAAANQAECgYIEgAAAA==.Shilajit:BAAANQAECgMIBgAAAA==.Shokz:BAAANQADCgMIAwABNQAECgMIAwABAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.',
Sm='Smokalot:BAAANQADCggICAAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgQIBAAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgcIHQAdABIcAA==.',
Sp='Speedbeefbal:BAAANQADCgMIAwAAAA==.Speeddwrfbal:BAAANQADCgYIBwAAAA==.Speedmeat:BAAANQAECgYICQAAAA==.Speedmonkbal:BAAANQADCgUIAwAAAA==.Speedoe:BAAANQADCgMIAwAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAABNQAECoEWAAIKAAcK8gV7lQB2AQAKAAcK8gV7lQB2AQAAAA==.',
Sq='Squal:BAAANQAECgUICAABNQAECgUICQABAAAAAA==.Squiggle:BAAANQAECgYIDAAAAA==.',
St='Steevii:BAAANQADCgMJAwAAAA==.Stewie:BAAANQAECgIIAwAAAA==.Striker:BAAANQADCgUICQABNQAECgYIDwABAAAAAA==.',
Su='Sunshíne:BAAANQAECgMIBAAAAA==.',
Sy='Syver:BAAANQAECgYICQAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAAANQAECgcICAAAAA==.Takeroux:BAAANQAECgEIAQAAAA==.Talandroz:BAABNQAECoEWAAMfAAgKeBsDDgCdAgAfAAgKeBsDDgCdAgAgAAIKTAskLQBmAAAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Tanner:BAABNQAECoEkAAIKAAkKxBtWLACqAgAKAAkKxBtWLACqAgAAAA==.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Tedman:BAAANQAECgYIDQAAAA==.Temel:BAAANQAECgYIDwAAAA==.Teostra:BAABNQAECoEVAAIKAAcKlh8ZOAB+AgAKAAcKlh8ZOAB+AgAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgABAAAAAA==.',
Th='Thadrack:BAAANQAECgcIEAAAAA==.Thalonstin:BAAANQADCgUIDQAAAA==.Thaneold:BAAANQAECgQJCQABNQAECggIIgAeAM0hAA==.Thassarian:BAAANQAECgQIBAABNQAECgQIBgABAAAAAA==.Theodrid:BAACNQAFFIEMAAIcAAUKWR4mAgC2AQAcAAUKWR4mAgC2AQA1AAQKgSMAAhwACQrXIpgEAEMDABwACQrXIpgEAEMDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAABNQAECoEaAAIIAAcKgBusEQASAgAIAAcKgBusEQASAgAAAA==.Tirzahdozier:BAAANQAECgEIAQABNQAECgIIBgABAAAAAA==.Tiwohnne:BAAANQADCggIEgAAAA==.',
Tl='Tla:BAAANQADCgUICQAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgUICgABAAAAAA==.',
Tr='Treat:BAAANQAECgYIDgAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAcIEgAPALEfAA==.Tristitia:BAAANQABCgYIBwAAAA==.',
Tu='Turkeltin:BAAANQAECgYICQABNQAECggIHAADAKAcAA==.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgIIBgABAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAAANQAECgUICwAAAA==.Tyche:BAAANQADCgUIBgAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAABNQAECoEaAAIhAAcK3SRaCwDfAgAhAAcK3SRaCwDfAgAAAA==.',
Va='Vains:BAABNQAECoEjAAIGAAgK7RxfPACZAgAGAAgK7RxfPACZAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velexi:BAAANQABCggIEgAAAA==.Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAAANQAECgQICAAAAA==.Verren:BAAANQAECgUIDQAAAA==.Vesfor:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Vestus:BAAANQABCgcICwAAAA==.',
Vy='Vyrridyl:BAAANQAECgIIBQAAAA==.',
Wa='Watermark:BAAANQAECgYIDwAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgUICgAAAA==.Weltazar:BAAANQAECgYICgAAAA==.Weltzilla:BAAANQAECgUICgAAAA==.Westside:BAAANQAECgYICQAAAA==.',
Wh='Whoosh:BAABNQAECoEbAAIMAAgK1iCjEwDkAgAMAAgK1iCjEwDkAgAAAA==.',
Wi='Wickët:BAABNQAECoEYAAMNAAcKByD+MABaAgANAAcKByD+MABaAgAaAAYKPiCUPgAxAgAAAA==.Wildtiger:BAAANQAECgUIDQAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Wu='Wulfenhide:BAAANQAECgYIEAAAAA==.',
Wy='Wyzsky:BAAANQADCgQIEgABNQAECgYIDwABAAAAAA==.',
Xa='Xalreth:BAAANQAECgUIDQAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAABNQAECoEZAAIVAAgKphEkSwD4AQAVAAgKphEkSwD4AQAAAA==.',
Za='Zarieda:BAAANQAECgcICwAAAA==.Zayrelia:BAABNQAECoEhAAMhAAkKpxhWFABgAgAhAAgKZRdWFABgAgAEAAYKtBYnQgCdAQAAAA==.',
Ze='Zelenor:BAAANQADCgMIAwABNQAECgUICwABAAAAAA==.',
Zu='Zud:BAAANQAECgYIEgAAAA==.',
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
