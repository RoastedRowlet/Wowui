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

local lookup = {'Priest-Holy','Shaman-Restoration','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Warlock-Demonology','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Warlock-Destruction','Paladin-Retribution','DeathKnight-Blood','Paladin-Protection','Hunter-Marksmanship','Warrior-Protection','Hunter-BeastMastery','Monk-Windwalker','Druid-Guardian','Druid-Restoration','Shaman-Elemental','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Druid-Feral','Monk-Brewmaster','Warrior-Fury','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCggICAAAAA==.Adwen:BAAANQADCgYIBgAAAA==.',
Ak='Akariala:BAAANQAECgUICgABNQAECggIHwABAAcOAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.',
Am='Amberlie:BAAANQAECggICQAAAA==.Aminni:BAABNQAECoEbAAICAAgKVxGBVQDkAQACAAgKVxGBVQDkAQAAAA==.Amorgal:BAAANQADCgUICQAAAA==.Amorir:BAAANQAECgYIDwAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAABNQAECoEVAAIDAAcKPA44TgB9AQADAAcKPA44TgB9AQAAAA==.Andeddo:BAABNQAECoElAAMEAAkKlxjGKwBkAgAEAAkKbxfGKwBkAgAFAAgK2xOXMgDZAQAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAABNQAECoEXAAIDAAkKrx2wFgD6AgADAAkKrx2wFgD6AgAAAA==.Ariodecay:BAAANQAECgIIAgAAAA==.Ariodh:BAACNQAFFIEMAAIGAAQKHSSVBwCSAQAGAAQKHSSVBwCSAQA1AAQKgSkAAgYACQp8JqsBANgDAAYACQp8JqsBANgDAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIBAAAAA==.Arnak:BAAANQADCgMJAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFIEKAAIHAAQKrQ0MFAApAQAHAAQKrQ0MFAApAQA1AAQKgScAAgcACQpYG8k9AH4CAAcACQpYG8k9AH4CAAAA.',
At='Athenà:BAAANQABCgQJBwAAAA==.',
Av='Avye:BAAANQAECgQICQAAAA==.',
Ba='Bananus:BAAANQAECgUIBQAAAA==.Banthr:BAAANQAECgUIEAAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.Benchedwin:BAAANQADCgcIBwAAAA==.',
Bi='Bigcow:BAAANQAECgYJEQAAAA==.Bigdeeps:BAABNQAECoEiAAIIAAkKVyMLEwBnAwAIAAkKVyMLEwBnAwAAAA==.',
Bl='Blackolives:BAABNQAECoEUAAIBAAgKox4JIgDJAgABAAgKox4JIgDJAgAAAA==.Blastcannon:BAABNQAECoEgAAMJAAgKKQTKGQD/AAAJAAcKYQTKGQD/AAAKAAQKugHSjgFnAAAAAA==.Bluejuly:BAAANQABCgQJBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECgkJMQALANYfAA==.',
Br='Bravehearth:BAAANQADCgYIBgABNQADCgUIBQAMAAAAAA==.',
Bu='Bubbadoo:BAABNQAECoEZAAIDAAcKghJdRQCuAQADAAcKghJdRQCuAQAAAA==.Bulan:BAABNQAECoEaAAINAAcKYiRdCQDaAgANAAcKYiRdCQDaAgAAAA==.',
Ca='Candypants:BAABNQAECoEbAAINAAcK9hqgEgAmAgANAAcK9hqgEgAmAgAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECoEdAAIJAAcKPyN+BAC6AgAJAAcKPyN+BAC6AgAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAAANQAECgUICQAAAA==.Cayssaris:BAAANQAECgQICQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECoEgAAMOAAgKth74AwC/AgAOAAgKYB74AwC/AgAPAAYKFRpqFgDEAQAAAA==.',
Ch='Chaewon:BAAANQAECgEIAQABNQAECggIDwAMAAAAAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chappedlips:BAAANQAECgEIAQAAAA==.Chidaka:BAAANQAECgEJAgABNQAECggIFwAQAJwfAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAABNQAECoEaAAMHAAkKxBVBbADyAQAHAAcKcRlBbADyAQARAAUKTAx+NADlAAAAAA==.Cosairi:BAAANQAECgYIEQAAAA==.Cougztroll:BAAANQAECgYIDwAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECggIEwAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECggIIAAOALYeAA==.',
Cu='Cuttercupx:BAAANQAECgUICgABNQAECgcIDQAMAAAAAA==.',
Da='Dakadin:BAABNQAECoEXAAIQAAgKnB9yHQDnAgAQAAgKnB9yHQDnAgAAAA==.Dalamarr:BAAANQAECgEIAQAAAA==.Daranne:BAABNQAECoEnAAISAAkK2Rq5QQCqAgASAAkK2Rq5QQCqAgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECoEiAAITAAcKCA4qWQBsAQATAAcKCA4qWQBsAQAAAA==.Dashy:BAAANQAECgQIBAAAAA==.Dawnstone:BAAANQAECgQICwAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAAANQAECgYJEAAAAA==.Deafsmash:BAAANQAECgIIBAABNQAECggIHgAEAFEeAA==.Delamyr:BAAANQABCgIJAwABNQADCgYIBgAMAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQAECgQICAAMAAAAAA==.Destroyevsky:BAAANQAECgIIBAAAAA==.Detonate:BAAANQADCgUICQAAAA==.',
Di='Digem:BAAANQABCgQJBAABNQADCgcIEwAMAAAAAA==.',
Do='Dolphinz:BAACNQAFFIEGAAMSAAQKWhNuEQD1AAASAAMKPhluEQD1AAAUAAIKCgYyDABYAAA1AAQKgSAAAxIACQo7I0ccAD0DABIACQo7I0ccAD0DABQABAqDFvo2AAYBAAAA.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJHAANACcfAA==.Dragonwarior:BAABNQAECoEXAAIIAAkKchCZkgDGAQAIAAkKchCZkgDGAQAAAA==.Drykkr:BAAANQAECgUIEgAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggICQAMAAAAAA==.Element:BAAANQADCgUIBQAAAA==.Elpollo:BAAANQAECgQIBAAAAA==.Elvar:BAAANQADCgYIDwAAAA==.',
Em='Emmdwemm:BAAANQADCgYIBgAAAA==.Emolo:BAAANQADCgMIAwABNQAECggIHAASAB4RAA==.',
Ep='Epitome:BAABNQAECoEZAAIJAAcKJRozCgD3AQAJAAcKJRozCgD3AQAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.',
Et='Etude:BAAANQAECgEIAQAAAA==.',
Eu='Eunha:BAAANQAECgUIBwABNQAECggIDwAMAAAAAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgcIIgATAAgOAA==.Evergrey:BAAANQAECgQIBAAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQADCggICgAAAA==.Falasdaer:BAAANQAECgQIBgAAAA==.Falstaff:BAAANQADCgcJDgAAAA==.Fatalis:BAAANQADCggIHgAAAA==.Fatterblunt:BAACNQAFFIEKAAIDAAQKiwpZEQAaAQADAAQKiwpZEQAaAQA1AAQKgScAAgMACQoFG3gmAH4CAAMACQoFG3gmAH4CAAAA.',
Fe='Feldar:BAABNQAECoEZAAISAAcKLhxvdAAWAgASAAcKLhxvdAAWAgAAAA==.Feronite:BAABNQAECoExAAILAAkK1h8IBQA0AwALAAkK1h8IBQA0AwAAAA==.',
Fi='Fizzleclaw:BAAANQAECgQICQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgQICQAMAAAAAA==.Fizzlelock:BAAANQADCgYIBgAAAA==.Fizzlesvoid:BAAANQADCgQIBAAAAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgQIDAAAAA==.',
Fr='Fredwin:BAAANQAECgcIDwAAAA==.Free:BAAANQADCgcIDQABNQAECgQIBAAMAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBAAMAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Ganthex:BAAANQADCgUJBQAAAA==.Gapper:BAABNQAECoEuAAIVAAkK7h/LCQAoAwAVAAkK7h/LCQAoAwAAAA==.Gardengnome:BAAANQADCgEIAQABNQAFFAQIDgAWAKwgAA==.Gargodath:BAAANQABCgYIDAAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAABNQAECoEXAAIXAAgK1B1CLgDAAgAXAAgK1B1CLgDAAgAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAABNQAECoEVAAIIAAgK6BH+dwAMAgAIAAgK6BH+dwAMAgAAAA==.',
Go='Gojira:BAAANQAECgQICQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECoEYAAMNAAcKXRstEwAdAgANAAcKXRstEwAdAgAYAAEKCA+hXwAwAAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECggIEwAPAHUJAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAAANQAECgQICQAAAA==.',
Ha='Haerin:BAAANQAECgUICAABNQAECggIDwAMAAAAAA==.Hairydresden:BAAANQABCgIIAgAAAA==.Harnel:BAAANQAECgUIEAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgEIAQAAAA==.Hellborne:BAAANQABCgIIAgAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQAMAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQAECgIIAgABNQAECgkJMQALANYfAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgQIBQAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAAANQAECgYIDAAAAA==.Kaliel:BAAANQADCgcIFwAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgUJBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICwAHAI8RAA==.',
Ke='Kernelpanic:BAACNQAFFIELAAQEAAQKRBsqCgBHAQAEAAQKORoqCgBHAQAFAAIKZBmJDgCkAAATAAEKYgE9MAAnAAA1AAQKgRwAAwQACApKIWsnAHwCAAQACApKIWsnAHwCAAUAAQolFnaOAD0AAAAA.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYIDgAAAA==.Kirkle:BAABNQAECoEkAAIRAAgKyxgwCAByAgARAAgKyxgwCAByAgAAAA==.',
Ko='Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYICgAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICwAHAI8RAA==.Krukar:BAAANQAECgQIBQAAAA==.',
Ku='Kulrath:BAAANQAECggICAAAAA==.',
Kw='Kwovie:BAABNQAECoEZAAIZAAgKORoGDQBXAgAZAAgKORoGDQBXAgAAAA==.',
Ky='Kynaria:BAAANQAECgEIAQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAABNQAECoEWAAISAAcKFRCcqACWAQASAAcKFRCcqACWAQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgQIBAABNQAECgQICAAMAAAAAA==.Lavasaurus:BAAANQAECgQICAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcICwAAAA==.Lewd:BAAANQAECgYIDwAAAA==.',
Li='Lifebloomz:BAABNQAECoEXAAMaAAcKjRLjKQCdAQAaAAcKjRLjKQCdAQAZAAEK3wHkXAAZAAAAAA==.Lilfluffcc:BAABNQAECoEZAAILAAgKuhC+EQAtAgALAAgKuhC+EQAtAgAAAA==.',
Lo='Lockward:BAAANQAECgcIEwAAAA==.Lorblor:BAABNQAECoEWAAIGAAcKUB63JQBGAgAGAAcKUB63JQBGAgAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQAECggICAAAAA==.',
Lu='Lucidlux:BAABNQAECoEbAAIbAAgKJxX6SAAmAgAbAAgKJxX6SAAmAgAAAA==.Lunafox:BAAANQAECggIEAAAAA==.Lunamae:BAABNQAECoEXAAIKAAYKmhDD9gB4AQAKAAYKmhDD9gB4AQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgkJJgABACUbAA==.Luvvyyaa:BAABNQAECoEmAAIBAAkKJRvpNAByAgABAAkKJRvpNAByAgAAAA==.Luvyya:BAAANQADCggICAABNQAECgkJJgABACUbAA==.',
Ly='Lythomancer:BAAANQAECgYIEQAAAA==.',
Ma='Maddeena:BAAANQAECgQICQAAAA==.Magicmandunz:BAAANQADCggIDgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFIELAAIHAAUKjxGOCwCJAQAHAAUKjxGOCwCJAQA1AAQKgTEAAgcACQp5Iv0QADkDAAcACQp5Iv0QADkDAAAA.',
Mc='Mcmercie:BAAANQAECggIEQAAAA==.',
Me='Mechacooter:BAABNQAECoEiAAIcAAkKQRoBFQCwAgAcAAkKQRoBFQCwAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAABNQAECoEaAAIKAAcKthHXxADXAQAKAAcKthHXxADXAQAAAA==.Melchiorr:BAABNQAECoErAAIdAAkK9RsqAgDtAgAdAAkK9RsqAgDtAgAAAA==.Melynne:BAAANQAECgYJDgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQIBwAMAAAAAA==.Minji:BAAANQAECgYICgABNQAECggIDwAMAAAAAA==.Minsoo:BAABNQAECoEbAAINAAkKNxo4DQCNAgANAAkKNxo4DQCNAgAAAA==.',
Ml='Mlrgl:BAAANQAECggIEwAAAA==.Mlrglo:BAAANQAECgUJBgABNQAECggIEwAMAAAAAA==.',
Mo='Mormegil:BAAANQAECgQICAAAAA==.Moshimoshi:BAABNQAFFIEFAAICAAIKRxILGwCXAAACAAIKRxILGwCXAAAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQAECgQICAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECgkJIgAcAEEaAA==.',
Ne='Nessará:BAABNQAECoEeAAIBAAgKwAfydQCBAQABAAgKwAfydQCBAQAAAA==.',
Ni='Nightgodjuju:BAAANQAECgUICQAAAA==.Nikna:BAAANQAECgUICwABNQAECgkJGwAXAIMaAA==.',
Nu='Nudacris:BAAANQAECggICwABNQAECggIEwAMAAAAAA==.Nuraga:BAAANQAECgYIEQAAAA==.',
Ny='Nytrissa:BAAANQAECgQIBAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQAECgUIEwAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAABNQAECoEcAAINAAkKJx/UBQAlAwANAAkKJx/UBQAlAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECgYICQAMAAAAAA==.Pattilicious:BAAANQAECgcIEgAAAA==.',
Ph='Phonedin:BAABNQAECoEbAAMPAAgKyxfNFADgAQAPAAcKvxbNFADgAQAeAAUKbxPaKQA7AQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECoEkAAIUAAgKJxL7HgDDAQAUAAgKJxL7HgDDAQAAAA==.',
Py='Pyrug:BAAANQADCgUIBQABNQAECgYJEAAMAAAAAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECggIHwAXAHENAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rannmagnison:BAABNQAECoEYAAISAAcKPAfX0wA5AQASAAcKPAfX0wA5AQAAAA==.Raquoon:BAAANQAECgQIBwAAAA==.Razzalghoul:BAABNQAECoEXAAMFAAcKtRILOwCjAQAFAAcKtRILOwCjAQAEAAQKYAaImwCiAAAAAA==.',
Re='Reidar:BAAANQABCgUIBQABNQAECgUIEAAMAAAAAA==.Reuli:BAAANQAECgIIAwAAAA==.Reze:BAABNQAECoEeAAIYAAkKBCItCwALAwAYAAkKBCItCwALAwABNQAFFAgIIAAGAKolAA==.',
Rh='Rhaeynera:BAAANQAECgUIDgAAAA==.',
Ri='Riezen:BAABNQAECoEaAAIEAAYKFBnuWgB9AQAEAAYKFBnuWgB9AQAAAA==.Rinorik:BAABNQAECoEaAAMHAAcKBx7DbgDqAQAHAAYKHx3DbgDqAQARAAIKyB/yPwC4AAAAAA==.',
Ro='Rockbiter:BAAANQADCgYIBgAAAA==.Rockhhard:BAAANQAECgIIAgAAAA==.Roeken:BAAANQAECgcIEwAAAA==.Rollingman:BAAANQAECgQIBAAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAABNQAECoEcAAITAAcK+yMPHAC2AgATAAcK+yMPHAC2AgAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAABNQAECoEWAAIVAAcKgCEHFgCVAgAVAAcKgCEHFgCVAgAAAA==.',
Sa='Samsó:BAABNQAECoEZAAMQAAcKgxXTXADfAQAQAAcKgxXTXADfAQASAAEKzBJScgE1AAAAAA==.Sapharina:BAABNQAECoEfAAIBAAgKBw4SaQCuAQABAAgKBw4SaQCuAQAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECoEdAAQfAAkKqx3EBgDSAgAfAAgK7x3EBgDSAgAaAAYKwBmjJgC8AQAZAAIK/xEaQQBhAAAAAA==.Schreckstoff:BAABNQAECoEYAAIbAAcK3xMtZADEAQAbAAcK3xMtZADEAQAAAA==.',
Se='Searfang:BAABNQAECoEiAAIbAAkKJhmHMgCKAgAbAAkKJhmHMgCKAgAAAA==.Sematic:BAAANQAECgEIAQABNQAFFAUIDwAIAJEfAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shashashmoo:BAABNQAECoEXAAIDAAcKAxCMTACHAQADAAcKAxCMTACHAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAAANQAECgUIEAAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skëëts:BAAANQADCgUIBQAAAA==.',
Sl='Slampoof:BAAANQABCggIDAAAAA==.Sleatsz:BAAANQADCggICAAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECggICAAAAA==.Slimesmile:BAAANQAECgMIBAAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAAMAAAAAA==.Smashmaster:BAAANQADCgEIAQAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwAMAAAAAA==.',
Sn='Snowscayia:BAABNQAECoFMAAMaAAkKDyHRBABnAwAaAAkKDyHRBABnAwADAAgKhxWMLgBFAgAAAA==.Snypes:BAABNQAECoEZAAIDAAkK/hw2HADMAgADAAkK/hw2HADMAgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAABNQAECoEaAAIJAAcKJhv+CAAZAgAJAAcKJhv+CAAZAgAAAA==.',
Sq='Squadie:BAABNQAECoEYAAIXAAcKNwsZkgCzAQAXAAcKNwsZkgCzAQAAAA==.Squanchs:BAABNQAECoEkAAICAAkKFSZeAgC1AwACAAkKFSZeAgC1AwABNQAECgYIBwAMAAAAAA==.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgcIBwAAAA==.',
St='Story:BAAANQADCgUICwAAAA==.Styrcius:BAABNQAECoEbAAIUAAcKIhxlFgAiAgAUAAcKIhxlFgAiAgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECgYICQAAAA==.Suniah:BAAANQAECgUIDAAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAUIDwAIAJEfAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQADCgcIBwAAAA==.Süß:BAAANQADCgIIAgABNQAECgkJHQAfAKsdAA==.',
Ta='Tabius:BAAANQAECgUIEgAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.',
Te='Tealle:BAAANQABCgIIAgABNQAECgQICAAMAAAAAA==.Teddumby:BAAANQADCgcICAABNQAECgcIDQAMAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAAANQAECgQICQAAAA==.',
Th='Thelorìn:BAAANQAECgYIEAAAAA==.Thiccdiq:BAABNQAECoEaAAIgAAcK5R6jCQBlAgAgAAcK5R6jCQBlAgAAAA==.Thiccgirl:BAAANQABCgMIBAAAAA==.Thirstycow:BAAANQAECgcIDgAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECoE4AAIXAAkKLCSXBgCeAwAXAAkKLCSXBgCeAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAABNQAECoElAAIDAAkKUxqxGwDQAgADAAkKUxqxGwDQAgAAAA==.Tråitors:BAAANQAECgUIDQAAAA==.',
Ts='Tsarevich:BAAANQAECgQICQAAAA==.',
Tw='Twileaf:BAAANQAECgUIDQAAAA==.',
Ul='Ully:BAAANQAECgMIBgAAAA==.',
Un='Unholyaltec:BAABNQAECoEeAAIEAAgKhBDTTgCwAQAEAAgKhBDTTgCwAQAAAA==.Unug:BAAANQADCggIDgABNQAECgYJEAAMAAAAAA==.',
Ut='Uthmansur:BAAANQAECgQIBgAAAA==.',
Va='Varkbyte:BAAANQAECgQICQAAAA==.Varrik:BAABNQAECoErAAMIAAgKsB8HPgC5AgAIAAgKsB8HPgC5AgAhAAEK0R3CKgA/AAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAABNQAECoEVAAMBAAcKfhPLawCkAQABAAcKfhPLawCkAQAiAAQKMwviFADBAAAAAA==.Voyageurs:BAABNQAECoEbAAIfAAgKkx1RCACgAgAfAAgKkx1RCACgAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggICQAMAAAAAA==.Vyrka:BAAANQAECgQICQAAAA==.',
['Vÿ']='Vÿc:BAAANQAECgMIBgABNQAECggIHwAKADQZAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wegl:BAAANQADCgMIAwAAAA==.Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgMIBAAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECgUIDQAMAAAAAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQAMAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgYIEwAAAA==.',
Wo='Wonhee:BAAANQAECggIBQABNQAECggIDwAMAAAAAA==.Wonyoung:BAAANQAECggIDwAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.',
Wu='Wuthrad:BAAANQAECgYIDwAAAA==.',
Wy='Wyze:BAAANQADCggIDgAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAABNQAECoEaAAMFAAcK5xyMKAAhAgAFAAcK5xyMKAAhAgAEAAIKMANcwQBGAAAAAA==.Xellor:BAAANQADCgYIBgAAAA==.Xelojr:BAAANQADCgYIGgAAAA==.',
Xi='Xia:BAAANQAECgYJEAAAAA==.Xilhaunt:BAABNQAECoEmAAQRAAkKgBwVBQDAAgARAAkKExkVBQDAAgAHAAgKXhdCSwBTAgAdAAQKShTqEgDyAAAAAA==.',
Xo='Xoilbiis:BAAANQADCgYIEQAAAA==.Xoilkick:BAAANQAECgYICgAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQAECgUIBQAAAA==.',
['Xê']='Xêna:BAAANQAECgUIBQAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgkJLgAVAO4fAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgYICgAAAA==.',
Za='Zaak:BAABNQAECoEdAAIjAAgKMSUnAQBkAwAjAAgKMSUnAQBkAwAAAA==.Zamari:BAAANQAECgQICAAAAA==.Zanzabar:BAAANQAECgYICQAAAA==.',
Ze='Zelfie:BAAANQAECgEJAQAAAA==.Zeliek:BAABNQAECoElAAIQAAkKJxqXHADrAgAQAAkKJxqXHADrAgABNQAECgkJJQAQACcaAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.',
Zo='Zoerina:BAAANQAECgYIDQAAAA==.Zoobilong:BAABNQAECoEcAAISAAgKHhHKgwDuAQASAAgKHhHKgwDuAQAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECggIHQAjADElAA==.',
['Zë']='Zën:BAABNQAECoEgAAMKAAgKYAn23QCmAQAKAAgKqwj23QCmAQAJAAEKCQ85RQAsAAAAAA==.',
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
