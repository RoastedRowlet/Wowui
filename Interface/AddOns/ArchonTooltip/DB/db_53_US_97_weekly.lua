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

local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Warlock-Demonology','Shaman-Enhancement','Druid-Balance','Monk-Windwalker','Druid-Restoration','Paladin-Holy','Warrior-Arms','Hunter-BeastMastery',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ak='Akariala:BAAANQADCgYICwABNQAECgYIDAABAAAAAA==.Akittymeow:BAAANQADCggIEwAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Alidar:BAAANQAECgQIBQAAAA==.',
Am='Amberlie:BAAANQAECgcIBwAAAA==.Aminni:BAAANQAECgUICQAAAA==.Amorgal:BAAANQADCgQIBAAAAA==.Amorir:BAAANQAECgUICQAAAA==.Amorydalias:BAAANQADCgcICQAAAA==.',
An='Anastala:BAAANQAECgQIBgAAAA==.Andeddo:BAAANQAECgcIEAAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQADCggIEwAAAA==.',
Ar='Archontas:BAAANQAECgUICwAAAA==.Ariodecay:BAAANQAECgIIAgAAAA==.Ariodh:BAABNQAECoEcAAICAAkJiSUeAQDYAwACAAkJiSUeAQDYAwAAAA==.Arkaline:BAAANQADCgMIAwAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUIBQAAAA==.Artuarry:BAABNQAECoEZAAIDAAkJnhlaGgCUAgADAAkJnhlaGgCUAgAAAA==.',
At='Athenà:BAAANQABCgQIBwAAAA==.',
Av='Avye:BAAANQADCggIFgAAAA==.',
Ba='Banthr:BAAANQAECgIIAgAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.',
Bi='Bigcow:BAAANQAECgUIDQAAAA==.Bigdeeps:BAAANQAECgYIEAAAAA==.',
Bl='Blackolives:BAAANQAECggICwAAAA==.Blastcannon:BAAANQAECgUICgAAAA==.Bluejuly:BAAANQABCgQIBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECggIIQAEAEsbAA==.',
Bu='Bubbadoo:BAAANQAECgQICQAAAA==.Bulan:BAAANQAECgQIBQAAAA==.',
Ca='Candypants:BAAANQAECgQICQAAAA==.Caoth:BAAANQAECgEIAQAAAA==.Cappilon:BAAANQAECgUICgAAAA==.Carcus:BAAANQAECgcIDAAAAA==.Cayleedah:BAAANQADCgcIDQAAAA==.Cayssaris:BAAANQADCggIFgAAAA==.',
Ce='Ceeti:BAAANQAECgYICwAAAA==.',
Ch='Chaoticoreo:BAAANQADCgUIBQAAAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgIIAgAAAA==.',
Co='Corva:BAAANQAECgcIEQAAAA==.Cosairi:BAAANQAECgQIBQAAAA==.Cougztroll:BAAANQAECgYICgAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECggIDgAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Cu='Cuttercupx:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.',
Da='Dakadin:BAAANQAECgUICQAAAA==.Daranne:BAAANQAECgQIBgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAAANQAECgQIDAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAAANQAECgYICgAAAA==.Deafsmash:BAAANQAECgIIAwABNQAECgMIBQABAAAAAA==.Delamyr:BAAANQABCgIIAwAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQADCggIFgABAAAAAA==.Destroyevsky:BAAANQADCgcIFwAAAA==.',
Di='Digem:BAAANQABCgQIBAABNQADCgcIEwABAAAAAA==.',
Do='Dolphinz:BAAANQAFFAEIAQAAAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgUICAABAAAAAA==.Dragonwarior:BAAANQAECgUICQAAAA==.Drykkr:BAAANQAECgUICQAAAA==.',
El='Elcrys:BAAANQADCggICgABNQAECgcIBwABAAAAAA==.Element:BAAANQADCgQIBAAAAA==.Elpollo:BAAANQADCggICQAAAA==.Elvar:BAAANQADCgUICAAAAA==.',
Ep='Epitome:BAAANQAECgQICQAAAA==.',
Er='Erid:BAAANQAECgMIAwAAAA==.',
Eu='Eunha:BAAANQADCggICAABNQAECgUIBgABAAAAAA==.',
Ev='Evergrey:BAAANQADCggIDgAAAA==.Evermoons:BAAANQAECgUICQAAAA==.',
Fa='Falaria:BAAANQADCgIIAgAAAA==.Falasdaer:BAAANQAECgQIBQAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fatalis:BAAANQADCggIFwAAAA==.Fatterblunt:BAABNQAECoEcAAIFAAkJPRj9FwCPAgAFAAkJPRj9FwCPAgAAAA==.',
Fe='Feldar:BAAANQAECgQIBQAAAA==.Feronite:BAABNQAECoEhAAIEAAgJSxvbBQC6AgAEAAgJSxvbBQC6AgAAAA==.',
Fi='Fizzleclaw:BAAANQADCgcIFwAAAA==.Fizzleded:BAAANQADCgIIAgABNQADCgcIFwABAAAAAA==.',
Fo='Fordi:BAAANQADCggIGgAAAA==.Fourdy:BAAANQAECgIIBQAAAA==.',
Fr='Fredwin:BAAANQADCgMIAwAAAA==.Free:BAAANQADCgcIDQAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgYICwABNQADCgcIDQABAAAAAA==.Furvert:BAAANQAECgcIDAAAAA==.',
Ga='Ganthex:BAAANQADCgUIBQAAAA==.Gapper:BAAANQAECggIEgAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAAANQAECgIIAwAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAAANQAECgEIAQAAAA==.',
Go='Gojira:BAAANQADCggIFgAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAAANQAECgQICgAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Grollosh:BAAANQABCgQIBgAAAA==.Grymwarr:BAAANQADCgcIFwAAAA==.',
Ha='Harnel:BAAANQAECgIIAgAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQADCgcIEQAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Hordedefect:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Hoyer:BAAANQADCggIEgAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.',
Ja='Jakub:BAAANQADCgIIAgABNQAECggIIQAEAEsbAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQADCgcIFwAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQADCggIFAAAAA==.',
Ka='Kaiserice:BAAANQADCgcIBwAAAA==.Kaliel:BAAANQADCgUICgAAAA==.Kamarra:BAAANQADCgcIDQAAAA==.Kamencider:BAAANQADCgQICAAAAA==.Karjo:BAAANQADCggIFAAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAECgkJJgADABwgAA==.',
Ke='Kernelpanic:BAAANQAFFAEIAQAAAA==.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kirkle:BAAANQAECgUICwAAAA==.',
Ko='Kovy:BAAANQADCgYICgAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAECgkJJgADABwgAA==.',
Kw='Kwovie:BAAANQAECgUICQAAAA==.',
Ky='Kynaria:BAAANQADCgUICAAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAAANQAECgQIBQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgQIBAAAAA==.Lavasaurus:BAAANQADCgcIEwABNQAECgQIBAABAAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgIIAgAAAA==.Lesclaypool:BAAANQADCgQIBAAAAA==.Lewd:BAAANQAECgQIBAAAAA==.',
Li='Lifebloomz:BAAANQAECgQIBQAAAA==.Lilfluffcc:BAAANQAECgUICgAAAA==.',
Lo='Lockward:BAAANQAECgYIDQAAAA==.Lorblor:BAAANQAECgQIBQAAAA==.Lowang:BAAANQADCgYICwAAAA==.Lowmeinn:BAAANQAECgQIBAAAAA==.',
Lt='Ltningbolt:BAAANQADCgUICgAAAA==.',
Lu='Lucidlux:BAAANQAECgcIBgAAAA==.Lunafox:BAAANQAECggIBgAAAA==.Lunamae:BAAANQAECgQICQAAAA==.Luvvyaa:BAAANQAECgQIBAABNQAECgcIDAABAAAAAA==.Luvvyyaa:BAAANQAECgcIDAAAAA==.Luvyya:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.',
Ly='Lythomancer:BAAANQAECgQIBAAAAA==.',
Ma='Maddeena:BAAANQADCgcIFwAAAA==.Magicmandunz:BAAANQADCggIDgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAABNQAECoEmAAIDAAkJHCCTBwA1AwADAAkJHCCTBwA1AwAAAA==.',
Mc='Mcmercie:BAAANQAECgYICAAAAA==.',
Me='Mechacooter:BAAANQAECggIEQAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAAANQAECgYIBgAAAA==.Melchiorr:BAAANQAECgYIEwAAAA==.Melynne:BAAANQAECgYICgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQIBwABAAAAAA==.Minsoo:BAAANQAECgYIDgAAAA==.',
Ml='Mlrgl:BAAANQADCgQIBAABNQAECgUIBgABAAAAAA==.Mlrglo:BAAANQAECgUIBgAAAA==.',
Mo='Mormegil:BAAANQADCgcIFwAAAA==.Moshimoshi:BAAANQAECgcICwAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQADCggIFgAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECggIEQABAAAAAA==.',
Ne='Nessará:BAAANQAECgQICQAAAA==.',
Ni='Nightgodjuju:BAAANQAECgUIBAAAAA==.Nikna:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
Nu='Nuraga:BAAANQAECgEIAgAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQAECgUICgAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAAANQAECgUICAAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQAAAA==.Pattilicious:BAAANQAECgUICgAAAA==.',
Ph='Phonedin:BAAANQAECgUICQAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAAANQAECgYIDwAAAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgYIBgABAAAAAA==.',
Qu='Quilue:BAAANQAECgMIAwAAAA==.',
Ra='Rannmagnison:BAAANQAECgQIBQAAAA==.Raquoon:BAAANQADCggIFQAAAA==.Razzalghoul:BAAANQAECgQIBQAAAA==.',
Re='Reze:BAABNQAECoEZAAIGAAkJ8CHpAwBXAwAGAAkJ8CHpAwBXAwABNQAFFAcIEQACAJEjAA==.',
Rh='Rhaeynera:BAAANQAECgEIAQAAAA==.',
Ri='Riezen:BAAANQAECgQIDQAAAA==.Rinorik:BAAANQAECgYIBgAAAA==.',
Ro='Rockhhard:BAAANQADCggIDgAAAA==.Roeken:BAAANQAECgQIBgAAAA==.Rollingman:BAAANQADCgcIEQAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAAANQAECgUICQAAAA==.Ruzala:BAAANQADCgIIAgAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAAANQAECgQIBAAAAA==.',
Sa='Samsó:BAAANQAECgQIBQAAAA==.Sapharina:BAAANQAECgYIDAAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAAANQAECgYIEAAAAA==.Schreckstoff:BAAANQAECgQICQAAAA==.',
Se='Searfang:BAAANQAECgYIEAAAAA==.Septik:BAAANQADCgQIBAAAAA==.',
Sh='Shadowmidget:BAAANQADCggIEwAAAA==.Shashashmoo:BAAANQAECgYIDwAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAAANQADCgcIBQAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.',
Sl='Sleatsz:BAAANQADCggICAAAAA==.Sleez:BAAANQADCggIDgAAAA==.Slimesmile:BAAANQAECgEIAQAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQADCggIEgABAAAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.',
Sn='Snowscayia:BAABNQAECoEkAAMHAAkJPh3NBgDgAgAHAAgJER7NBgDgAgAFAAgJaQvuKgDRAQAAAA==.Snypes:BAAANQAECggIEgAAAA==.',
So='Socks:BAAANQADCgYICAAAAA==.Solanar:BAABNQAECoEYAAIIAAkJ3xUQEwDIAgAIAAkJ3xUQEwDIAgAAAA==.Solmina:BAAANQAECgYIBgAAAA==.',
Sq='Squadie:BAAANQAECgQIBQAAAA==.Squanchs:BAAANQAECgcIEwABNQAECgIIAgABAAAAAA==.Squanchy:BAAANQAECgIIAgAAAA==.',
Sr='Srry:BAAANQAECgIIAgAAAA==.',
St='Story:BAAANQADCgMIAwAAAA==.Styrcius:BAAANQAECgUICAAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Suniah:BAAANQADCggIFwAAAA==.Sustmage:BAAANQAECgIIAQABNQAECgkJGgAJAJUkAA==.',
['Sü']='Sünny:BAAANQADCgcIBwAAAA==.Süß:BAAANQADCgIIAgABNQAECgYIEAABAAAAAA==.',
Ta='Tabius:BAAANQAECgUICQAAAA==.Talkingtaco:BAAANQAECgEIAgAAAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDAABAAAAAA==.Temok:BAAANQADCgcIFwAAAA==.',
Th='Thelorìn:BAAANQADCgMIAwAAAA==.Thiccdiq:BAAANQAECgYIBgAAAA==.Thirstycow:BAAANQABCgcIBwAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQADCggIEgAAAA==.',
To='Tore:BAABNQAECoEaAAIKAAgJZCSuCABJAwAKAAgJZCSuCABJAwAAAA==.',
Tr='Trinadel:BAAANQAECgcIEwAAAA==.Tråitors:BAAANQAECgMIBAAAAA==.',
Ts='Tsarevich:BAAANQADCggIFgAAAA==.',
Tw='Twileaf:BAAANQAECgIIAgAAAA==.',
Ul='Ully:BAAANQAECgEIAQAAAA==.',
Un='Unholyaltec:BAAANQAECgYICwAAAA==.Unug:BAAANQABCgQIBgABNQAECgYICgABAAAAAA==.',
Ut='Uthmansur:BAAANQADCgYIBgAAAA==.',
Va='Varkbyte:BAAANQADCggIFgAAAA==.Varrik:BAAANQAECgYIEAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.',
Vi='Vivrae:BAAANQADCgQIBAAAAA==.',
Vo='Voleandre:BAAANQAECgQIDAAAAA==.Voyageurs:BAAANQAECgYIDwAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECgcIBwABAAAAAA==.Vyrka:BAAANQADCggIFQAAAA==.',
['Vÿ']='Vÿc:BAAANQADCgEIAQAAAA==.',
Wa='Waterdweller:BAAANQADCgUIBgAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wetheals:BAAANQADCgEIAQAAAA==.',
Wh='Whatmurda:BAAANQADCgYIEAABNQAECgMIBAABAAAAAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDAABAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgUIDQAAAA==.',
Wo='Wonyoung:BAAANQAECgUIBgAAAA==.',
Wr='Wraithwok:BAAANQADCggIDwAAAA==.',
Wu='Wuthrad:BAAANQAECgQIBAAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAAANQAECgQICAAAAA==.Xelojr:BAAANQADCgUIEQAAAA==.',
Xi='Xia:BAAANQAECgYICgAAAA==.Xilhaunt:BAAANQAECgcIDwAAAA==.',
Xo='Xoilbiis:BAAANQADCgYICwAAAA==.Xoilkick:BAAANQAECgQIBAAAAA==.Xoilwings:BAAANQADCgMIAwAAAA==.',
['Xê']='Xêna:BAAANQADCggIFAAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQAECgMIAwABNQAECggIEgABAAAAAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgQIBAAAAA==.',
Za='Zaak:BAAANQAECgUICQAAAA==.Zamari:BAAANQADCgYIFgAAAA==.Zanzabar:BAAANQAECgQIBAAAAA==.',
Ze='Zelfie:BAAANQAECgEIAQAAAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.',
Zo='Zoerina:BAAANQAECgQIBQAAAA==.Zoobilong:BAAANQAECgYICQAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECgUICQABAAAAAA==.',
['Zë']='Zën:BAAANQAECgYIDAAAAA==.',
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
