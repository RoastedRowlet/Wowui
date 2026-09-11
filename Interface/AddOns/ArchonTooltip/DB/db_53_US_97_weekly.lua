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

local lookup = {'Unknown-Unknown','Shaman-Enhancement','Warlock-Demonology','DemonHunter-Havoc',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-09-08',data={Ak='Akariala:BAAANQADCgUIBQABNQAECgQIBgABAAAAAA==.Akittymeow:BAAANQADCgYIEQAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Alidar:BAAANQAECgQIBAAAAA==.',
Am='Amberlie:BAAANQADCgYICwABNQADCggICgABAAAAAA==.Aminni:BAAANQAECgQIBAAAAA==.Amorgal:BAAANQADCgQIBAAAAA==.Amorir:BAAANQAECgUIBAAAAA==.Amorydalias:BAAANQADCgMIAgAAAA==.',
An='Anastala:BAAANQAECgEIAgAAAA==.Andeddo:BAAANQAECgYICwAAAA==.Annelya:BAAANQADCgcIBwAAAA==.',
Ar='Archontas:BAAANQAECgUIBwAAAA==.Ariodecay:BAAANQADCgYIBgAAAA==.Ariodh:BAAANQAECggIEwAAAA==.Arkaline:BAAANQADCgMIAwAAAA==.Arnak:BAAANQADCgMIAwAAAA==.Arpeggio:BAAANQADCgUIBQAAAA==.Artuarry:BAAANQAECgcIEAAAAA==.',
At='Athenà:BAAANQABCgQIBwAAAA==.',
Av='Avye:BAAANQADCgcIDgAAAA==.',
Ba='Banthr:BAAANQAECgEIAQAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.',
Bi='Bigcow:BAAANQAECgUICQAAAA==.Bigdeeps:BAAANQAECgUICgAAAA==.',
Bl='Blackolives:BAAANQAECgYIBgAAAA==.Blastcannon:BAAANQAECgQIBQAAAA==.Bluejuly:BAAANQABCgQIBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIBgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECggIFwACANoYAA==.',
Bu='Bubbadoo:BAAANQAECgQIBQAAAA==.Bulan:BAAANQAECgEIAQAAAA==.',
Ca='Candypants:BAAANQAECgQIBQAAAA==.Caoth:BAAANQAECgEIAQAAAA==.Cappilon:BAAANQAECgQIBQAAAA==.Carcus:BAAANQAECgUICAAAAA==.Cayleedah:BAAANQADCgcIDQAAAA==.Cayssaris:BAAANQADCgcIDgAAAA==.',
Ce='Ceeti:BAAANQAECgUIBQAAAA==.',
Ch='Chaoticoreo:BAAANQADCgUIBQAAAA==.',
Co='Corva:BAAANQAECgYICwAAAA==.Cosairi:BAAANQAECgEIAQAAAA==.Cougztroll:BAAANQAECgUIBAAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECggIDQAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Cu='Cuttercupx:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.',
Da='Dakadin:BAAANQAECgQIBAAAAA==.Daranne:BAAANQAECgIIAgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAAANQAECgQIBAAAAA==.',
De='Dead:BAAANQADCgYIBgAAAA==.Deaduglie:BAAANQAECgUIBAAAAA==.Deafsmash:BAAANQAECgEIAQAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQADCgcIDgABAAAAAA==.Destroyevsky:BAAANQADCgcIEAAAAA==.',
Di='Digem:BAAANQABCgQIBAABNQADCgYIDAABAAAAAA==.',
Do='Dolphinz:BAAANQAECgcICQAAAA==.',
Dr='Dragonkyle:BAAANQADCgYICgABNQAECgMIAwABAAAAAA==.Dragonwarior:BAAANQAECgQIBAAAAA==.Drykkr:BAAANQAECgQIBAAAAA==.',
El='Elcrys:BAAANQADCggICgAAAA==.Element:BAAANQADCgQIBAAAAA==.Elpollo:BAAANQADCgEIAQAAAA==.Elvar:BAAANQADCgQIBgAAAA==.',
Ep='Epitome:BAAANQAECgQIBQAAAA==.',
Ev='Evergrey:BAAANQADCggIDgAAAA==.Evermoons:BAAANQAECgQIBAAAAA==.',
Fa='Falaria:BAAANQADCgIIAgAAAA==.Falasdaer:BAAANQAECgEIAQAAAA==.Falstaff:BAAANQADCgcIDgAAAA==.Fatalis:BAAANQADCggIDwAAAA==.Fatterblunt:BAAANQAECgcIEQAAAA==.',
Fe='Feldar:BAAANQAECgEIAQAAAA==.Feronite:BAABNQAECoEXAAICAAgJ2hgmBQB+AgACAAgJ2hgmBQB+AgAAAA==.',
Fi='Fizzleclaw:BAAANQADCgYIEAAAAA==.Fizzleded:BAAANQADCgIIAgABNQADCgYIEAABAAAAAA==.',
Fo='Fordi:BAAANQADCggIEwAAAA==.Fourdy:BAAANQAECgIIBAAAAA==.',
Fr='Free:BAAANQADCgcIDQAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Furvert:BAAANQAECgcIDAAAAA==.',
Ga='Gapper:BAAANQAECgcICwAAAA==.',
Gl='Glestaar:BAAANQAECgIIAgAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAAANQADCgQIBAAAAA==.',
Go='Gojira:BAAANQADCgcIDgAAAA==.Gothri:BAAANQAECgQIBgAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Grymwarr:BAAANQADCgYIEAAAAA==.',
Ha='Harnel:BAAANQADCggIFAAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQADCgYICgAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Hordedefect:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.',
Ja='Jakub:BAAANQADCgIIAgABNQAECggIFwACANoYAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQADCgYIEAAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQADCggIFAAAAA==.',
Ka='Kaiserice:BAAANQADCgcIBwAAAA==.Kaliel:BAAANQADCgUICgAAAA==.Kamarra:BAAANQADCgcIDQAAAA==.Kamencider:BAAANQADCgQIBAAAAA==.Karjo:BAAANQADCgcIDAAAAA==.',
Ke='Kernelpanic:BAAANQAECgcICwAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kirkle:BAAANQAECgQIBgAAAA==.',
Ko='Kovy:BAAANQADCgYICgAAAA==.',
Kw='Kwovie:BAAANQAECgQIBAAAAA==.',
Ky='Kynaria:BAAANQADCgUICAAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAAANQAECgEIAQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Lavamancer:BAAANQAECgQIBAAAAA==.Lavasaurus:BAAANQADCgYIDAABNQAECgQIBAABAAAAAA==.',
Le='Leafstorm:BAAANQADCgYIDAAAAA==.Leokenoso:BAAANQADCgcIEQAAAA==.Lesclaypool:BAAANQADCgQIBAAAAA==.Lewd:BAAANQAECgQIBAAAAA==.',
Li='Lifebloomz:BAAANQAECgEIAQAAAA==.Lilfluffcc:BAAANQAECgQIBwAAAA==.',
Lo='Lockward:BAAANQAECgUIBwAAAA==.Lorblor:BAAANQAECgIIAgAAAA==.Lowang:BAAANQADCgYICwAAAA==.Lowmeinn:BAAANQAECgQIBAAAAA==.',
Lt='Ltningbolt:BAAANQADCgUICgAAAA==.',
Lu='Lunafox:BAAANQAECggIBgAAAA==.Lunamae:BAAANQAECgQIBQAAAA==.Luvvyyaa:BAAANQAECgQIBQAAAA==.',
Ly='Lythomancer:BAAANQADCgcIEgAAAA==.',
Ma='Maddeena:BAAANQADCgYIEAAAAA==.Magicmandunz:BAAANQADCggIDgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAABNQAECoEZAAIDAAkJ9h2lBgD9AgADAAkJ9h2lBgD9AgAAAA==.',
Mc='Mcmercie:BAAANQAECgIIAwAAAA==.',
Me='Mechacooter:BAAANQAECgcICwAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAAANQADCggIFwAAAA==.Melchiorr:BAAANQAECgYIDQAAAA==.Melynne:BAAANQAECgUIBAAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQIBwABAAAAAA==.Minsoo:BAAANQAECgUICAAAAA==.',
Ml='Mlrglo:BAAANQADCgUIBgAAAA==.',
Mo='Mormegil:BAAANQADCgYIEAAAAA==.Moshimoshi:BAAANQAECgcICgAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgEIAQAAAA==.',
Na='Naberius:BAAANQADCgcIDgAAAA==.Nagahunter:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECgcICwABAAAAAA==.',
Ne='Nessará:BAAANQAECgQIBQAAAA==.',
Ni='Nightgodjuju:BAAANQAECgUIBAAAAA==.Nikna:BAAANQABCgYICAABNQAECgcICwABAAAAAA==.',
Nu='Nuraga:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQAECgQIBQAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAAANQAECgMIAwAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQAAAA==.Pattilicious:BAAANQAECgQIBQAAAA==.',
Ph='Phonedin:BAAANQAECgQIBAAAAA==.',
Po='Powerochrist:BAAANQAECgYICgAAAA==.',
['Pá']='Pád:BAAANQAECgQIBgAAAA==.',
Qu='Quilue:BAAANQAECgEIAQAAAA==.',
Ra='Rannmagnison:BAAANQAECgEIAQAAAA==.Raquoon:BAAANQADCgcIDQAAAA==.Razzalghoul:BAAANQAECgEIAQAAAA==.',
Re='Reze:BAAANQAECggIEgABNQAFFAYICgAEAN0fAA==.',
Rh='Rhaeynera:BAAANQAECgEIAQAAAA==.',
Ri='Riezen:BAAANQAECgQICQAAAA==.Rinorik:BAAANQADCggIDwAAAA==.',
Ro='Roeken:BAAANQAECgIIAgAAAA==.Rollingman:BAAANQADCgYICgAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAAANQAECgMIBAAAAA==.Ruzz:BAAANQADCgcIDgAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAAANQADCgYICAAAAA==.',
Sa='Samsó:BAAANQAECgEIAQAAAA==.Sapharina:BAAANQAECgQIBgAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAAANQAECgYICgAAAA==.Schreckstoff:BAAANQAECgQIBQAAAA==.',
Se='Searfang:BAAANQAECgYICgAAAA==.Septik:BAAANQADCgQIBAAAAA==.',
Sh='Shadowmidget:BAAANQADCgYIEQAAAA==.Shashashmoo:BAAANQAECgYICgAAAA==.Shlum:BAAANQADCgYIDAAAAA==.',
Si='Silaslunark:BAAANQADCgUIBQAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.',
Sl='Sleez:BAAANQADCgYIBgAAAA==.Slimesmile:BAAANQADCggIFAAAAA==.',
Sm='Smøk:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.',
Sn='Snowscayia:BAAANQAECgcIEwAAAA==.Snypes:BAAANQAECgUICgAAAA==.',
So='Socks:BAAANQADCgIIAgAAAA==.Solanar:BAAANQAECggIEgAAAA==.Solmina:BAAANQADCggIDwAAAA==.',
Sq='Squadie:BAAANQAECgEIAQAAAA==.Squanchs:BAAANQAECgcIDAABNQADCggIDQABAAAAAA==.Squanchy:BAAANQADCggIDQAAAA==.',
Sr='Srry:BAAANQAECgEIAQAAAA==.',
St='Story:BAAANQADCgMIAwAAAA==.Styrcius:BAAANQAECgMIAwAAAA==.Stôrmfang:BAAANQADCgcICQAAAA==.',
Su='Sustmage:BAAANQAECgIIAQABNQAECggIEwABAAAAAA==.',
['Sü']='Süß:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.',
Ta='Tabius:BAAANQAECgQIBAAAAA==.Talkingtaco:BAAANQAECgEIAQAAAA==.',
Te='Temok:BAAANQADCgYIEAAAAA==.',
Th='Thiccdiq:BAAANQADCggIFwAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQADCgYICgAAAA==.',
To='Tore:BAAANQAECggIEAAAAA==.',
Tr='Trinadel:BAAANQAECgcIDAAAAA==.Tråitors:BAAANQAECgEIAQAAAA==.',
Ts='Tsarevich:BAAANQADCgcIDgAAAA==.',
Tw='Twileaf:BAAANQADCggIFAAAAA==.',
Ul='Ully:BAAANQADCggIEgAAAA==.',
Un='Unholyaltec:BAAANQAECgEIAQAAAA==.',
Ut='Uthmansur:BAAANQADCgYIBgAAAA==.',
Va='Varkbyte:BAAANQADCgcIDgAAAA==.Varrik:BAAANQAECgYICgAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Vo='Voleandre:BAAANQAECgQICAAAAA==.Voyageurs:BAAANQAECgYICQAAAA==.',
Vy='Vynn:BAAANQADCgEIAQABNQADCggICgABAAAAAA==.Vyrka:BAAANQADCgcIDQAAAA==.',
['Vÿ']='Vÿc:BAAANQADCgEIAQAAAA==.',
Wa='Waterdweller:BAAANQADCgUIBgAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wetheals:BAAANQADCgEIAQAAAA==.',
Wh='Whatmurda:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.Whosurpally:BAAANQADCgQIBAAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgQICAAAAA==.',
Wo='Wonyoung:BAAANQAECgEIAQAAAA==.',
Wr='Wraithwok:BAAANQADCggIDwAAAA==.',
Wu='Wuthrad:BAAANQAECgQIBAAAAA==.',
Xa='Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAAANQAECgQICAAAAA==.Xelojr:BAAANQADCgUIDAAAAA==.',
Xi='Xia:BAAANQAECgUIBAAAAA==.Xilhaunt:BAAANQAECgUICAAAAA==.',
Xo='Xoilbiis:BAAANQADCgYICwAAAA==.Xoilkick:BAAANQADCggIDwAAAA==.',
['Xê']='Xêna:BAAANQADCggIFAAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQADCgcICwABNQAECgcICwABAAAAAA==.',
Yu='Yumeshade:BAAANQADCgcIBwAAAA==.',
Za='Zaak:BAAANQAECgQIBAAAAA==.Zamari:BAAANQADCgYIEAAAAA==.Zanzabar:BAAANQADCgcICAAAAA==.',
Ze='Zelfie:BAAANQAECgEIAQAAAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIBgAAAA==.',
Zo='Zoerina:BAAANQAECgUIBAAAAA==.Zoobilong:BAAANQAECgIIAwAAAA==.',
Zx='Zxak:BAAANQADCggICAABNQAECgQIBAABAAAAAA==.',
['Zë']='Zën:BAAANQAECgUIBgAAAA==.',
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
