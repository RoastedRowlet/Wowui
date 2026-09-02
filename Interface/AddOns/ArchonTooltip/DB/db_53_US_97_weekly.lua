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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-09-01',data={Ak='Akariala:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Akittymeow:BAAANQADCgYICwAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Alidar:BAAANQADCgUICAAAAA==.',
Am='Amberlie:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Aminni:BAAANQADCggICAAAAA==.Amorir:BAAANQADCgcIBwAAAA==.Amorydalias:BAAANQADCgMIAgAAAA==.',
An='Anastala:BAAANQAECgEIAQAAAA==.Andeddo:BAAANQAECgQIBQAAAA==.Annesta:BAAANQADCgYICwAAAA==.',
Ar='Archontas:BAAANQAECgIIAgAAAA==.Ariodecay:BAAANQADCgYIBgAAAA==.Ariodh:BAAANQAECgcICwAAAA==.Arkaline:BAAANQADCgMIAwAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUIBQAAAA==.Artuarry:BAAANQAECgUICQAAAA==.',
Av='Avye:BAAANQADCgUIBwAAAA==.',
Ba='Banthr:BAAANQADCggIDgAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.',
Bi='Bigcow:BAAANQAECgQIBAAAAA==.Bigdeeps:BAAANQAECgQIBQAAAA==.',
Bl='Blackolives:BAAANQAECgUIBQAAAA==.Blastcannon:BAAANQAECgEIAQAAAA==.',
Bo='Bomboclat:BAAANQAECgEIAQAAAA==.Bowwie:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.',
Bu='Bubbadoo:BAAANQAECgEIAQAAAA==.Bulan:BAAANQADCgcIDQAAAA==.',
Ca='Candypants:BAAANQAECgEIAQAAAA==.Caoth:BAAANQADCgYICgAAAA==.Cappilon:BAAANQAECgEIAQAAAA==.Carcus:BAAANQAECgMIAwAAAA==.Cayleedah:BAAANQADCgcIDQAAAA==.Cayssaris:BAAANQADCgUIBwAAAA==.',
Ce='Ceeti:BAAANQADCggIDwAAAA==.',
Ch='Chaoticoreo:BAAANQADCgUIBQAAAA==.',
Co='Corva:BAAANQAECgMIBQAAAA==.Cosairi:BAAANQADCgYIBgAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECgEIAQAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Da='Dakadin:BAAANQADCggIDgAAAA==.Daranne:BAAANQADCggIDQAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAAANQADCgUIDQAAAA==.',
De='Deaduglie:BAAANQADCgUIBQAAAA==.Deafsmash:BAAANQADCgEIAQAAAA==.Destroyevsky:BAAANQADCgUICQAAAA==.',
Do='Dolphinz:BAAANQAECgcIAgAAAA==.',
Dr='Dragonkyle:BAAANQADCgQIBAAAAA==.Dragonwarior:BAAANQADCggIDgAAAA==.Drykkr:BAAANQADCggIDgAAAA==.',
El='Elcrys:BAAANQADCgYIBgAAAA==.Element:BAAANQADCgQIBAAAAA==.Elvar:BAAANQADCgIIAgAAAA==.',
Ep='Epitome:BAAANQAECgEIAQAAAA==.',
Ev='Evergrey:BAAANQADCgYIBgAAAA==.Evermoons:BAAANQADCggIDgAAAA==.',
Fa='Falaria:BAAANQADCgIIAgAAAA==.Falasdaer:BAAANQADCgYIBgAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fatalis:BAAANQADCgYICAAAAA==.Fatterblunt:BAAANQAECgUICgAAAA==.',
Fe='Feldar:BAAANQADCgcIDQAAAA==.Feronite:BAAANQAECgUICQAAAA==.',
Fi='Fizzleclaw:BAAANQADCgYICgAAAA==.Fizzleded:BAAANQADCgIIAgABNQADCgYICgABAAAAAA==.',
Fo='Fordi:BAAANQADCgcICwAAAA==.Fourdy:BAAANQAECgIIAgAAAA==.',
Fr='Free:BAAANQADCgcIBwAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQABCgQIBAABNQADCgcIBwABAAAAAA==.Furvert:BAAANQAECgUIBQAAAA==.',
Ga='Gapper:BAAANQAECgQIBAAAAA==.',
Gl='Glestaar:BAAANQADCgYIBgAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Go='Gojira:BAAANQADCgUIBwAAAA==.Gothri:BAAANQAECgEIAQAAAA==.',
Gr='Grimli:BAAANQADCgQIBAAAAA==.Grymwarr:BAAANQADCgYICgAAAA==.',
Ha='Harnel:BAAANQADCgcIDAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQADCgQIBAAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Hordedefect:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.Hoyer:BAAANQADCgYICgAAAA==.',
Hu='Humbledrink:BAAANQABCgQIBAAAAA==.',
Ja='Jakub:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Jamous:BAAANQADCgYIBgAAAA==.',
Je='Jesit:BAAANQADCgYICgAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQADCggIDAAAAA==.',
Ka='Kaliel:BAAANQADCgQIBQAAAA==.Kamarra:BAAANQADCgYIBgAAAA==.Karjo:BAAANQADCgcICgAAAA==.',
Ke='Kernelpanic:BAAANQAECgQIBAAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kirkle:BAAANQAECgIIAgAAAA==.',
Ko='Kovy:BAAANQADCgYICgAAAA==.',
Kw='Kwovie:BAAANQADCggIDgAAAA==.',
Ky='Kynaria:BAAANQADCgMIBQAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAAANQADCgcIDQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Lavamancer:BAAANQADCgcICwAAAA==.Lavasaurus:BAAANQADCgYIBgAAAA==.',
Le='Leafstorm:BAAANQADCgYIBgAAAA==.Leokenoso:BAAANQADCgYICgAAAA==.Lesclaypool:BAAANQADCgQIBAAAAA==.Lewd:BAAANQADCgYIBgAAAA==.',
Li='Lifebloomz:BAAANQADCgcIDgAAAA==.Lilfluffcc:BAAANQAECgMIAwAAAA==.',
Lo='Lockward:BAAANQAECgIIAgAAAA==.Lorblor:BAAANQADCgcICgAAAA==.Lowang:BAAANQADCgYICwAAAA==.',
Lt='Ltningbolt:BAAANQADCgUIBQAAAA==.',
Lu='Lucidlux:BAAANQADCggIDwAAAA==.Lunamae:BAAANQAECgEIAQAAAA==.Luvvyyaa:BAAANQAECgQIBAAAAA==.',
Ly='Lythomancer:BAAANQADCgcIDAAAAA==.',
Ma='Maddeena:BAAANQADCgYICgAAAA==.Magicmandunz:BAAANQADCgYIBgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAAANQAECgcICwAAAA==.',
Mc='Mcmercie:BAAANQABCgIIBAAAAA==.',
Me='Mechacooter:BAAANQAECgQIBAAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAAANQADCggIDwAAAA==.Melchiorr:BAAANQAECgQIBwAAAA==.Melynne:BAAANQADCgcIBwAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgMIAwABAAAAAA==.Minsoo:BAAANQAECgMIAwAAAA==.',
Ml='Mlrglo:BAAANQADCgEIAQAAAA==.',
Mo='Mormegil:BAAANQADCgYICgAAAA==.Moshimoshi:BAAANQAECgQIBAAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQADCgcIBwAAAA==.',
Na='Naberius:BAAANQADCgUIBwAAAA==.Nagahunter:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECgQIBAABAAAAAA==.',
Ne='Nessará:BAAANQAECgEIAQAAAA==.',
Ni='Nightgodjuju:BAAANQADCgcIBwAAAA==.',
Nu='Nuraga:BAAANQADCggIDQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQADCggICAAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAAANQADCgcICwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQAAAA==.Pattilicious:BAAANQAECgEIAQAAAA==.',
Ph='Phonedin:BAAANQADCgcIBwAAAA==.',
Po='Powerochrist:BAAANQAECgQIBAAAAA==.',
['Pá']='Pád:BAAANQAECgIIAgAAAA==.',
Qu='Quilue:BAAANQADCgYIBgAAAA==.',
Ra='Rannmagnison:BAAANQADCgcIDQAAAA==.Raquoon:BAAANQADCgUIBgAAAA==.Razzalghoul:BAAANQADCgcIBwAAAA==.',
Re='Reze:BAAANQAECgYIDAABNQAFFAQIBAABAAAAAA==.',
Rh='Rhaeynera:BAAANQADCgcIDAAAAA==.',
Ri='Riezen:BAAANQAECgMIAwAAAA==.Rinorik:BAAANQADCggIDwAAAA==.',
Ro='Rockhhard:BAAANQADCgYICwAAAA==.Roeken:BAAANQAECgIIAgAAAA==.Rollingman:BAAANQADCgQIBAAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAAANQAECgEIAQAAAA==.Ruzz:BAAANQADCgUIBwAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAAANQADCgYICAAAAA==.',
Sa='Samsó:BAAANQADCgcIDQAAAA==.Sapharina:BAAANQAECgIIAgAAAA==.',
Sc='Scharf:BAAANQAECgIIAwAAAA==.Schreckstoff:BAAANQAECgEIAQAAAA==.',
Se='Searfang:BAAANQAECgQIBAAAAA==.',
Sh='Shadowmidget:BAAANQADCgYICwAAAA==.Shashashmoo:BAAANQAECgQIBAAAAA==.Shlum:BAAANQADCgQIBgAAAA==.',
Si='Silaslunark:BAAANQADCgUIBQAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.',
Sl='Slimesmile:BAAANQADCgcIDAAAAA==.',
Sn='Snowscayia:BAAANQAECgYICgAAAA==.Snypes:BAAANQAECgQIBQAAAA==.',
So='Solanar:BAAANQAECgUICgAAAA==.Solmina:BAAANQADCggIDwAAAA==.',
Sq='Squadie:BAAANQADCgcIDAAAAA==.Squanchs:BAAANQAECgUICQABNQADCgUIBQABAAAAAA==.Squanchy:BAAANQADCgUIBQAAAA==.',
Sr='Srry:BAAANQAECgEIAQAAAA==.',
St='Story:BAAANQADCgMIAwAAAA==.Styrcius:BAAANQADCgcIBwAAAA==.Stôrmfang:BAAANQADCgcIBwAAAA==.',
Su='Suniah:BAAANQADCgcIBwAAAA==.',
['Sü']='Süß:BAAANQADCgIIAgABNQAECgIIAwABAAAAAA==.',
Ta='Tabius:BAAANQADCggIDgAAAA==.Talkingtaco:BAAANQADCgcIDAAAAA==.',
Te='Temok:BAAANQADCgYICgAAAA==.',
Th='Thiccdiq:BAAANQADCggIDwAAAA==.Thorkell:BAAANQADCgYIBgAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQADCgUIBAAAAA==.',
To='Tore:BAAANQAECgcICAAAAA==.',
Tr='Trinadel:BAAANQAECgUIBQAAAA==.',
Ts='Tsarevich:BAAANQADCgUIBwAAAA==.',
Tw='Twileaf:BAAANQADCgcIDAAAAA==.',
Ul='Ully:BAAANQADCgYICgAAAA==.',
Un='Unholyaltec:BAAANQADCgMIAwAAAA==.',
Ut='Uthmansur:BAAANQADCgYIBgAAAA==.',
Va='Varkbyte:BAAANQADCgUIBwAAAA==.Varrik:BAAANQAECgMIBAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Vo='Voleandre:BAAANQAECgQIBAAAAA==.Voyageurs:BAAANQAECgMIAwAAAA==.',
Vy='Vynn:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Vyrka:BAAANQADCgUIBgAAAA==.',
['Vÿ']='Vÿc:BAAANQADCgEIAQAAAA==.',
Wa='Wayhigh:BAAANQADCgIIAgAAAA==.',
Wh='Whatmurda:BAAANQADCgYICgAAAA==.Wheredergo:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgQIBAAAAA==.',
Wo='Wonyoung:BAAANQAECgEIAQAAAA==.',
Wr='Wraithwok:BAAANQADCgcIBwAAAA==.',
Xa='Xandboni:BAAANQADCgEIAQAAAA==.',
Xe='Xelienn:BAAANQAECgIIBAAAAA==.Xelojr:BAAANQADCgUIBgAAAA==.',
Xi='Xia:BAAANQADCgcIBwAAAA==.Xilhaunt:BAAANQAECgQIBAAAAA==.',
Xo='Xoilbiis:BAAANQADCgUIBQAAAA==.Xoilkick:BAAANQADCggIDwAAAA==.',
['Xê']='Xêna:BAAANQADCgcIDAAAAA==.',
Yb='Yb:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.',
Za='Zaak:BAAANQADCggIDAAAAA==.Zamari:BAAANQADCgQICgAAAA==.Zanzabar:BAAANQADCgcICAAAAA==.',
Zo='Zoerina:BAAANQADCggIDgAAAA==.Zoobilong:BAAANQAECgIIAwAAAA==.',
['Zë']='Zën:BAAANQAECgEIAQAAAA==.',
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
