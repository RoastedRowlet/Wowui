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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Unknown-Unknown','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Druid-Restoration','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Priest-Shadow','DeathKnight-Frost','DemonHunter-Vengeance','Evoker-Augmentation',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abaddôn:BAAANQADCgYIBgAAAA==.',
Ad='Adirolf:BAAANQADCgUIBQAAAA==.',
Ae='Aenlori:BAAANQADCgYIBgABNQAFFAUJCgABAEMOAA==.Aenlorie:BAACNQAFFIEKAAIBAAUKQw6aBQCTAQABAAUKQw6aBQCTAQA1AAQKgSgABAEACQrbC5s7AAkCAAEACQrbC5s7AAkCAAIABQp4EjCgACsBAAMABAqUE98qAPUAAAAA.',
Ag='Ag:BAAANQADCgMIAgAAAA==.Agesilaus:BAAANQADCgEIAQAAAA==.Aggathon:BAEANQAECgUJBwAAAA==.',
Ak='Akebono:BAAANQADCgUJBQAAAA==.',
Al='Aldebaran:BAAANQAECgIJAwAAAA==.Alphatanker:BAABNQAECoEjAAIEAAkKyyUEAQDgAwAEAAkKyyUEAQDgAwAAAA==.',
Ar='Argentino:BAAANQAECgEJAQAAAA==.',
As='Ashke:BAAANQAECgYJDQAAAA==.',
Au='Aurica:BAAANQAECgEIAQAAAA==.',
Ax='Axes:BAAANQAECgEJAQAAAA==.',
Ba='Badlucklouie:BAAANQAECgUICgAAAA==.Badpenny:BAAANQADCgUJCwAAAA==.Bajenkas:BAAANQADCgYIBgAAAA==.Balfas:BAAANQAECgUJBQAAAA==.',
Be='Beaupeep:BAAANQADCgYIHQAAAA==.',
Bi='Bindicrippa:BAAANQADCgcIFAAAAA==.',
Bl='Blackwater:BAAANQAECgYJEAAAAA==.Bloodstyx:BAAANQADCggJEAABNQAECgYJDgAFAAAAAA==.',
Bo='Bobi:BAAANQADCggICQAAAA==.Boyacky:BAAANQABCgcICQAAAA==.',
Br='Braiglock:BAAANQAECgMJAQAAAA==.',
Bu='Bucko:BAAANQAECgQIBwAAAA==.',
By='Bygz:BAAANQAECgUICAABNQAFFAUJCwAGAOciAA==.',
Ca='Caarjack:BAABNQAECoEcAAMHAAgKMRpjDgB0AgAHAAgKMRpjDgB0AgAIAAQKFBjsGwAnAQAAAA==.Callmefury:BAAANQADCggJDgAAAA==.Callmemommy:BAAANQADCgUIBQAAAA==.Casserole:BAAANQAECgYJDgAAAA==.Catadelic:BAAANQAECgUJCwAAAA==.',
Ce='Celestial:BAAANQAECgUJCgAAAA==.',
Ch='Chewwbacca:BAAANQAECgYIDAAAAA==.Chewwy:BAAANQADCgUIBQABNQAECgYIDAAFAAAAAA==.Chewwyy:BAAANQADCgIIAgABNQAECgYIDAAFAAAAAA==.Chud:BAAANQADCgYICQAAAA==.Chuwy:BAAANQADCgMIAwABNQAECgYIDAAFAAAAAA==.',
Cl='Clap:BAAANQADCgYIBgAAAA==.',
Cu='Cudi:BAAANQAECgEIAwAAAA==.Cuzigothigh:BAAANQABCgEIAQAAAA==.',
Da='Darkdemon:BAAANQAECgcIEAAAAA==.Darkladyann:BAAANQAECgUIBQABNQAECgYIEQAFAAAAAA==.',
De='Deadlee:BAAANQAECgQIBgAAAA==.Deathphish:BAAANQAECgUJCwAAAA==.Dentfry:BAAANQAECgQJBgAAAA==.Derfla:BAAANQADCgUIBQAAAA==.Dezign:BAAANQAFFAEIAQABNQAFFAUJCAAJAFogAA==.',
Di='Dildro:BAAANQAECgEJAQAAAA==.Ditlutz:BAAANQAECgQIBgAAAA==.',
Do='Dom:BAABNQAECoEcAAIGAAkKFh2XLQC0AgAGAAkKFh2XLQC0AgAAAA==.Doronjo:BAAANQADCgYICQAAAA==.Dotrammy:BAAANQADCgcICQAAAA==.',
Du='Dupeslicate:BAAANQAECgMJBAAAAA==.',
Dw='Dwanco:BAAANQADCgEIAQAAAA==.Dwarfussy:BAAANQADCgMIAwAAAA==.',
Dy='Dybby:BAAANQAECgIJBAAAAA==.Dylexek:BAAANQADCgEIAQAAAA==.Dynamite:BAAANQADCgQIBAAAAA==.',
El='Elderoth:BAAANQAECgQICAAAAA==.Elfsky:BAAANQADCgUJBQAAAA==.',
En='Endlessnight:BAAANQAECgYJDgAAAA==.',
Er='Erica:BAAANQAECgQIBAAAAA==.',
['Eä']='Eärendil:BAAANQAECgIJAgAAAA==.',
Fa='Faebryn:BAAANQADCggIFAAAAA==.Faevor:BAAANQAECgQIBgAAAA==.',
Fe='Fenirean:BAAANQAECgQJBAAAAA==.',
Fl='Flirts:BAAANQADCgYJCgAAAA==.',
Fo='Forcas:BAAANQAECgUIBwAAAA==.',
Ga='Gamarrick:BAAANQAECgQIBwAAAA==.',
Ge='Germain:BAAANQADCgIIAgAAAA==.',
Gn='Gnometzu:BAAANQADCgYIBgAAAA==.',
Go='Golddicmove:BAAANQADCgEIAQAAAA==.',
Gr='Gremmel:BAAANQADCgcICQAAAA==.Griever:BAABNQAECoEiAAQKAAgKZhqDKwD8AAALAAQKyxgJjgAdAQAKAAMK+R2DKwD8AAAMAAEKGBYCGwBPAAAAAA==.',
Gu='Guillak:BAAANQAECgUIBwAAAA==.',
Ha='Hammond:BAAANQADCgMICAAAAA==.Hanraktah:BAAANQADCgUJBQAAAA==.Harlem:BAAANQABCgQIBAAAAA==.Harxx:BAAANQADCgQJBAAAAA==.Hatka:BAAANQADCggJEwAAAA==.Hattori:BAAANQABCgMIAwAAAA==.',
Hi='Higurashi:BAAANQABCgQIBgAAAA==.',
Ho='Holymanson:BAAANQAECgMJAwAAAA==.Hoofington:BAAANQAECgIJAgAAAA==.Howlingdoom:BAAANQADCgYIBgAAAA==.',
Hy='Hylexerr:BAAANQAECgEIAgAAAA==.',
Ib='Ibull:BAAANQADCgQIBQAAAA==.',
If='Iffy:BAAANQAECgYJCwAAAA==.',
Il='Ilian:BAAANQAECgYJDgAAAA==.',
In='Iniquity:BAAANQADCggJFAAAAA==.',
Ja='Jabiso:BAAANQAECgMIBQAAAA==.Jackthebeast:BAAANQAECgEIAQABNQAECgkJFwANALofAA==.Jackthefel:BAAANQAECgQJBQABNQAECgkJFwANALofAA==.Jackthetotem:BAABNQAECoEXAAINAAkKuh83DQBPAwANAAkKuh83DQBPAwAAAA==.Jain:BAAANQAECgEIAQAAAA==.',
Jd='Jdmagisdruid:BAAANQAECgQIBgAAAA==.',
Je='Jeanne:BAAANQAECgIIBAAAAA==.',
Jo='Jorcingmyshi:BAAANQAECgYJCwAAAA==.Jorhmont:BAAANQADCgUIBQAAAA==.',
Ju='Juan:BAAANQAECgQIBwAAAA==.Jumpeor:BAACNQAFFIEKAAICAAYKehzeAABCAgACAAYKehzeAABCAgA1AAQKgScAAgIACQqXJmMBAPADAAIACQqXJmMBAPADAAAA.',
Ka='Kanig:BAAANQADCggJEgAAAA==.Kassey:BAAANQADCgUJDAAAAA==.Katacola:BAACNQAFFIERAAIOAAUKYBt3AQDYAQAOAAUKYBt3AQDYAQA1AAQKgSIAAg4ACQolJIwCAH8DAA4ACQolJIwCAH8DAAAA.',
Ke='Kenaf:BAAANQADCgQIBAAAAA==.Kendrys:BAAANQAECgYJCQAAAA==.Kevenal:BAAANQAECgcIBwAAAA==.',
Ki='Kikiliki:BAAANQAECgMJBQAAAA==.Kinneas:BAAANQAECgQJBQAAAA==.',
Kl='Klënz:BAAANQAECgEIAQAAAA==.',
Ko='Koa:BAAANQAECgQIBAAAAA==.',
Ku='Kurau:BAAANQAECgQIBQAAAA==.Kurzal:BAAANQADCggJEwAAAA==.',
Ky='Kyraz:BAAANQAFFAMIAwABNQAFFAUJCwAGAOciAA==.',
La='Lacie:BAAANQAECgUJBwAAAA==.',
Le='Lexy:BAAANQAECgEIAQABNQAECgUJCgAFAAAAAA==.',
Lo='Lokiel:BAAANQAECgQICAAAAA==.Lokifurion:BAAANQAECgMJAwAAAA==.',
Lu='Lunitari:BAAANQADCgcJFgAAAA==.',
Ma='Magrat:BAAANQADCgIIAgAAAA==.Mahu:BAAANQADCgYIBgAAAA==.Maletherion:BAAANQAECgQIBgAAAA==.Maltherion:BAAANQAECgYIDgAAAA==.Margareetah:BAAANQADCgYJEwAAAA==.',
Me='Meglamonk:BAAANQAECgEIAQAAAA==.',
Mi='Milarca:BAAANQABCgYJCwAAAA==.Minireaper:BAAANQADCgMIAwAAAA==.',
Mj='Mjolnir:BAAANQAECgQIBgAAAA==.',
Mo='Mochizuko:BAAANQABCgIIAgAAAA==.Mongke:BAAANQABCgQIBAAAAA==.Moonre:BAAANQADCgYJDQAAAA==.',
Mu='Mubvan:BAAANQABCgMJAwAAAA==.Mushroommans:BAAANQAECgIJAwABNQAECggIHgAPAMQiAA==.',
Na='Namôr:BAAANQADCgUJDAAAAA==.Narzel:BAAANQADCggJHwAAAA==.Nashîr:BAAANQAECgUJCAAAAA==.Navybum:BAAANQAECgIIAgAAAA==.',
Ne='Nehemiah:BAAANQAECgQICQAAAA==.Nequin:BAAANQAECgYICgABNQAECgUJCAAFAAAAAA==.Nequins:BAAANQAECgMJAwABNQAECgUJCAAFAAAAAA==.Nequinss:BAAANQAECgUJCAAAAA==.Nevermore:BAAANQAECgEIAQAAAA==.',
Ni='Nicabar:BAAANQAECgYJEQAAAA==.Nilfheim:BAAANQADCggJDwAAAA==.',
No='Noehtyar:BAAANQAECgEJAQAAAA==.Noie:BAAANQAECgUJBQAAAA==.Novä:BAAANQAECgQIBAAAAA==.Noztalgia:BAAANQAECgIJAwAAAA==.',
['Në']='Nëklaüs:BAAANQAECgQICAAAAA==.',
Od='Odanarratite:BAAANQAECgEIAQAAAA==.Odanarrayne:BAAANQADCgcIBwAAAA==.Oditte:BAAANQABCgYICQAAAA==.',
Oi='Oilliphéist:BAAANQAECgEIAQAAAA==.',
Or='Ornot:BAABNQAECoEZAAIQAAgKew7eSgC9AQAQAAgKew7eSgC9AQAAAA==.',
Os='Oshdruid:BAAANQADCgYICwAAAA==.',
Pa='Pandurbear:BAAANQADCgUJDAAAAA==.Paperplate:BAAANQADCgcIEwABNQAECgUJBQAFAAAAAA==.Paws:BAAANQADCgMJBgAAAA==.',
Pe='Peposhammy:BAAANQADCgUIBQAAAA==.',
Ph='Phuulith:BAAANQADCgUJBQAAAA==.',
Pi='Picantechode:BAAANQADCgIJAgAAAA==.',
Pr='Provost:BAAANQAECgYIDQAAAA==.',
Ps='Psychonoia:BAAANQAECgQJBAAAAA==.',
Pu='Pumperdogx:BAAANQADCgYIBgABNQAECgkJIwAEAMslAA==.Pumpkinpîe:BAAANQADCgYIBgAAAA==.',
Qu='Quadritrix:BAAANQADCgQIBAAAAA==.Quanx:BAAANQAECgcICAAAAA==.Quark:BAAANQAECgIIAgAAAA==.',
Ra='Ratacola:BAAANQAECgQIBgAAAA==.',
Re='Remulüs:BAAANQAECgUJCgAAAA==.Reoãn:BAAANQABCgQIBgABNQADCgUIBQAFAAAAAA==.',
Ri='Riah:BAAANQADCgEIAQAAAA==.Riilyn:BAAANQAECgYJDgAAAA==.',
['Rø']='Røean:BAAANQADCgUIBQAAAA==.',
Sa='Sanktis:BAAANQADCggIFgAAAA==.',
Sb='Sbcarpenter:BAAANQADCgUJBQAAAA==.',
Sc='Scawmfhealz:BAAANQABCgMIAwAAAA==.Scecretzs:BAAANQADCgYIEQAAAA==.',
Se='Sebone:BAAANQADCggIDQAAAA==.Secretz:BAAANQADCgcJCwAAAA==.Sedrelari:BAAANQAECgYIEwAAAA==.Sepsis:BAAANQAECgEIAQAAAA==.Serjaime:BAAANQABCgQJCAAAAA==.Sesamo:BAABNQAECoEYAAICAAcKJR6AQgBJAgACAAcKJR6AQgBJAgAAAA==.',
Sh='Shadedstørmz:BAAANQADCgIJAwAAAA==.Shocks:BAAANQAECgEJAQAAAA==.Shé:BAAANQAECgYJDQAAAA==.',
Si='Sixoneseven:BAAANQADCgQIBAAAAA==.Sixseven:BAAANQAECgYJCwAAAA==.',
Sk='Skaarlett:BAAANQABCgYIBAAAAA==.Skone:BAAANQAECgUICgAAAA==.',
Sm='Smarthen:BAAANQABCgQJBAABNQAECgYICAAFAAAAAA==.',
Sn='Snickers:BAAANQAECgYJDAAAAA==.',
So='Solarian:BAAANQAECgUIBwAAAA==.',
St='Startle:BAAANQADCgUJDAAAAA==.Steelbreeze:BAAANQADCgYJFQAAAA==.Storms:BAABNQAECoEcAAMRAAgK7SCnSwCoAgARAAgKgh2nSwCoAgAJAAMKBiKeEAAkAQAAAA==.Stoutbringer:BAAANQADCgYIFQAAAA==.Stride:BAAANQABCgMIAwABNQAECgYIDAAFAAAAAA==.',
Sy='Sylvaedir:BAAANQADCggICQAAAA==.',
['Sö']='Sören:BAAANQAECgIJAwAAAA==.',
Te='Teaka:BAAANQADCgYICgAAAA==.Tenspeed:BAAANQAECgQIBwAAAA==.Terellesguy:BAAANQADCgQIBAABNQAECgUICgAFAAAAAA==.Tetsuro:BAAANQADCgUIBwAAAA==.',
Th='Thire:BAAANQADCgcICwABNQAECgUICgAFAAAAAA==.Throwglaive:BAAANQAECgEIAQABNQAFFAUJCwAGAOciAA==.',
Ti='Tidereign:BAAANQAECgEIAQAAAA==.Tinytotems:BAAANQAECgUICQAAAA==.Tiriell:BAAANQAECgcJEwAAAA==.',
To='Toe:BAAANQAECgMIAwAAAA==.',
Tr='Trausti:BAAANQAECgUJCQAAAA==.Treehen:BAAANQAECgYICAAAAA==.Trinanah:BAABNQAECoEcAAISAAgKrw6UHADqAQASAAgKrw6UHADqAQAAAA==.Troltsky:BAAANQADCgQIBAAAAA==.',
Va='Valariann:BAAANQADCggICAAAAA==.Valeriux:BAAANQADCgUJAwAAAA==.Valgal:BAAANQADCgYIEwAAAA==.Valiraste:BAAANQAECgYIEQAAAA==.Varalina:BAAANQAECgQJBgAAAA==.',
Vi='Viital:BAAANQADCgYIBgAAAA==.Vischar:BAAANQADCgUIBwAAAA==.',
Vo='Voidmommy:BAAANQABCgEIAQAAAA==.',
Wa='Washbeans:BAABNQAECoEhAAITAAkKyx3jDwCwAgATAAkKyx3jDwCwAgAAAA==.',
We='Wef:BAAANQAECgMIBAAAAA==.',
Wh='Whyse:BAAANQAECgUJBQAAAA==.',
Wi='Wings:BAAANQAECgYIDAAAAA==.Wintel:BAAANQADCgIIAgAAAA==.',
Xa='Xanza:BAAANQADCgUJCAAAAA==.',
Ya='Yamzaio:BAAANQADCgUJBwAAAA==.',
Yo='Yo:BAAANQADCgcIDAAAAA==.',
Za='Zancrafter:BAAANQADCgIIAgABNQAECgkJHQAPAF4YAA==.Zanduwuin:BAABNQAECoEdAAMPAAkKXhg4DwDDAgAPAAkKXhg4DwDDAgAUAAMKRglhFwCBAAAAAA==.Zanvoker:BAABNQAECoEaAAMVAAkK8BdUBABdAgAVAAkKphdUBABdAgAIAAYKLBMHFgCMAQABNQAECgkJHQAPAF4YAA==.Zargar:BAAANQAECgIJAwAAAA==.',
Zo='Zorttok:BAAANQAECgEIAQAAAA==.',
Zu='Zukkario:BAACNQAFFIELAAIGAAUK5yIBBAAAAgAGAAUK5yIBBAAAAgA1AAQKgSAAAgYACQpSJjgGAKwDAAYACQpSJjgGAKwDAAAA.',
['Âx']='Âxel:BAAANQAECgYIDQAAAA==.',
['År']='Årgon:BAAANQAECgcIEAAAAA==.',
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
