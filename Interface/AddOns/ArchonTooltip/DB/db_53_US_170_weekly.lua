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
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Absol:BAAANQAECgQIBAAAAA==.',
Ac='Achilles:BAAANQAECgQIBQAAAA==.',
Ah='Ahsokatano:BAAANQADCggIDgAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.',
Ak='Akasha:BAAANQABCgIIBAAAAA==.Akos:BAAANQADCggIDQABNQAECgQIBgABAAAAAA==.',
Al='Alzaeryan:BAAANQADCgMIAwAAAA==.',
Am='Amonet:BAAANQADCgQIBAAAAA==.',
An='Anamis:BAAANQADCggIDwAAAA==.Angras:BAAANQADCgIIAgAAAA==.',
Ap='Aphalock:BAAANQADCggIDwAAAA==.',
Ar='Ariûs:BAAANQADCgYICgAAAA==.Arlorian:BAAANQADCgYICwAAAA==.Arrowsmites:BAAANQADCggICAAAAA==.',
As='Askelad:BAAANQADCgQIBQAAAA==.',
Au='Aubani:BAAANQADCggICAAAAA==.',
Ay='Ayperos:BAAANQAECgEIAQAAAA==.',
Ba='Bakedpally:BAAANQAECgEIAQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQADCgcIDAAAAA==.',
Be='Beavur:BAAANQADCggICAAAAA==.Beck:BAAANQADCggIDwAAAA==.Bereth:BAAANQADCgQIBAAAAA==.Berreydingle:BAAANQADCgMIAwAAAA==.',
Bi='Bigkitty:BAAANQADCgcIDQAAAA==.',
Bl='Blitzedbust:BAAANQADCgUIBQAAAA==.Bluesummer:BAAANQADCgcIDgABNQADCggIEAABAAAAAA==.',
Bo='Bobeh:BAAANQADCgYIDAABNQABCgIIAgABAAAAAA==.Borat:BAAANQADCggIDAABNQADCgIIAgABAAAAAA==.Borsam:BAAANQABCgQIBAAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQADCgQIBAAAAA==.Brom:BAAANQADCgYICwAAAA==.',
['Bè']='Bètflèch:BAAANQADCgUIBQAAAA==.',
Ca='Cad:BAAANQADCgYIBwAAAA==.Calytrix:BAEANQAECgMIAwAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgMIAwAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAAANQADCggICAAAAA==.',
Ch='Charsifood:BAAANQADCgYIDAAAAA==.Cheatpriest:BAAANQAECgMIAwAAAA==.Chepis:BAAANQADCgQIBAAAAA==.Chesthyr:BAAANQADCgcICQAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAAANQAECgEIAQAAAA==.Coldvengance:BAAANQADCggIDwAAAA==.',
Cr='Crazh:BAAANQAECgEIAQAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcIDQAAAA==.',
Cy='Cymindel:BAAANQAECgMIAwAAAA==.',
Da='Dakotà:BAAANQADCgYICwAAAA==.Darc:BAAANQADCgQIBAAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.',
De='Dejno:BAAANQAECgQIBAAAAA==.Dezign:BAAANQAECggICwAAAA==.',
Dr='Dragonmage:BAAANQADCgQIBAAAAA==.Drakma:BAAANQADCgQICAAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAAANQAECgMIAwAAAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.',
['Dö']='Dötdötdead:BAAANQADCgMIAwAAAA==.',
Ef='Effinsick:BAAANQADCggIBwAAAA==.',
Ei='Eisheth:BAAANQADCgQIBQAAAA==.',
El='Ellysiaa:BAAANQADCgYICAAAAA==.',
Em='Emmakyn:BAAANQADCggIDwAAAA==.',
Ey='Eyedontknow:BAAANQADCgYICwAAAA==.',
Ez='Ezzka:BAAANQADCgcIDQABNQAECgEIAQABAAAAAA==.',
Fa='Failroots:BAAANQADCggIDgAAAA==.Farzix:BAAANQADCgYIBgAAAA==.Façade:BAAANQAECgIIAgAAAA==.',
Fe='Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQADCgYICgAAAA==.Finnw:BAAANQABCgQIBAAAAA==.Firelite:BAAANQADCgEIAQABNQADCgUICgABAAAAAA==.',
Fl='Flairadin:BAAANQADCggIDwAAAA==.Flexo:BAAANQADCgYIBgAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQADCgYIBgAAAA==.Frowdawn:BAAANQADCggICQAAAA==.',
Ga='Garythenpc:BAAANQADCgQIBAAAAA==.',
Gl='Glacialkitty:BAAANQADCggICAAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Googoobler:BAAANQADCgUICQAAAA==.Goudanight:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Goudatime:BAAANQADCgYICwABNQADCgcIDQABAAAAAA==.',
Gr='Greenmagus:BAAANQADCgMIBQAAAA==.Grenadon:BAAANQADCgQIBAAAAA==.',
Ha='Hakibalboa:BAAANQAECgQIBAAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Hazard:BAAANQADCggIDwAAAA==.',
He='Hellboii:BAAANQADCgYIBgAAAA==.Heyitsrat:BAAANQADCgYICgAAAA==.',
Ho='Holo:BAAANQAECgYIBgAAAA==.Housemom:BAAANQADCgUIBQAAAA==.',
Ic='Icculus:BAAANQADCgcIDAAAAA==.',
Im='Iminyou:BAAANQADCgcIBwAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgMIAwABAAAAAA==.',
Ja='Jaenei:BAAANQADCgQIBAAAAA==.Janet:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Je='Jeeb:BAAANQAECgIIAgAAAA==.',
Ji='Jinxta:BAAANQADCggIDwAAAA==.',
Jo='Joansnow:BAAANQADCgIIAgAAAA==.Joeeo:BAAANQAECgEIAQAAAA==.',
Ju='July:BAAANQADCgQIBAAAAA==.',
Ka='Kaimargonar:BAAANQADCgUIBQAAAA==.Kaitoi:BAAANQADCgYICgAAAA==.Kamakizeg:BAAANQADCggIDgAAAA==.Katimalice:BAAANQADCgMIBQAAAA==.',
Ke='Keyzeus:BAAANQADCgcIDAAAAA==.',
Kh='Khui:BAAANQAECgYICQAAAA==.',
Ki='Killatu:BAAANQABCgIIAgAAAA==.Killerdeath:BAAANQADCgEIAQAAAA==.',
Kn='Knìghtmàrè:BAAANQAECgYICQAAAA==.',
Ko='Koltharaz:BAAANQAECgcICQAAAA==.Korloff:BAAANQADCgMIAwAAAQ==.',
Kr='Krazylock:BAAANQADCgQIBAAAAA==.',
Ku='Kungfuupanda:BAAANQADCgcIDQAAAA==.',
La='Lateralus:BAAANQAECgYICAAAAA==.Latt:BAAANQADCgQIBgABNQAECgYICAABAAAAAA==.Lawluss:BAAANQAECgEIAQAAAA==.',
Le='Legacyshot:BAAANQADCgQIBwAAAQ==.',
Li='Lightguard:BAAANQADCgcIAwAAAA==.Lighthouse:BAAANQAECgIIAgAAAA==.',
Lo='Lolhahabaha:BAAANQADCgYIBgAAAA==.Lorax:BAAANQAECgEIAQAAAA==.',
Lu='Luckÿ:BAAANQADCgUIBQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAAANQADCggIDwAAAA==.',
['Lï']='Lïllïth:BAAANQADCgYIDAAAAA==.',
['Ló']='Lóla:BAAANQADCgYIBgAAAA==.',
Ma='Madeah:BAAANQAECgEIAQAAAA==.Madforge:BAAANQADCggIDgAAAA==.Magegrizz:BAAANQADCggIDgAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAAANQAECgQIBQAAAA==.Mariacuras:BAAANQADCgUIBwAAAA==.Marijwana:BAAANQADCggICwAAAA==.Martis:BAAANQADCgUIAgAAAA==.Marynne:BAAANQADCggIDgAAAA==.Mazuko:BAAANQADCggICgAAAA==.',
Me='Mecandry:BAAANQADCgcIDAAAAA==.Meepe:BAAANQADCgcIDAAAAA==.Melivant:BAAANQADCgYIDgAAAA==.Meranda:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.Merriklade:BAAANQADCgcICQAAAA==.Merrikoid:BAAANQADCgYICgAAAA==.',
Mi='Mico:BAAANQADCgUIBQAAAA==.',
Mo='Morbidstyle:BAAANQADCgcIDAABNQAECgQIBAABAAAAAA==.Morgoth:BAAANQAECgMIAwAAAA==.Morthos:BAAANQADCgMIAwAAAA==.Mosry:BAAANQADCggIDwAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECgMIAwABAAAAAA==.Mythundirus:BAAANQADCgcICwAAAA==.',
['Mà']='Màrli:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâgs:BAAANQADCggICAAAAA==.',
Na='Nakasid:BAAANQAECgMIBAAAAA==.Nashoba:BAAANQADCgYIBwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Neins:BAAANQADCgQIBAAAAA==.Nevaehstar:BAAANQAECgUICAAAAA==.',
Ni='Nik:BAAANQADCgYICwAAAA==.Nikolia:BAAANQADCgEIAQAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Os='Osoroshi:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.',
Pa='Patronous:BAAANQADCgYIDAAAAA==.',
Po='Polog:BAAANQADCgUICAABNQAECgEIAQABAAAAAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAAANQADCggIEAAAAA==.',
Pu='Puca:BAAANQADCgQIBAAAAA==.Pumdmuc:BAAANQADCgcICgABNQAECgEIAQABAAAAAA==.',
Qu='Quikglaives:BAAANQADCggICAAAAA==.Quille:BAAANQAECgMIAwAAAA==.',
Ra='Ragretts:BAAANQADCgYICQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgQIBAAAAA==.Raysdknight:BAAANQADCgIIAgAAAA==.',
Re='Redrek:BAAANQADCgUIBQAAAA==.Redwinter:BAAANQADCggIEAAAAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAAANQAECgQIBgAAAA==.',
Ri='Riqua:BAAANQADCgcICwAAAA==.',
Ro='Rockmonsta:BAAANQADCgYICAAAAA==.Roxies:BAAANQADCgQIBAAAAA==.',
Rp='Rpg:BAAANQAECgMIBAAAAA==.',
Sa='Saeti:BAAANQAECgMIAwAAAA==.Sapplesauce:BAAANQADCggICAAAAA==.',
Se='Seethrowwar:BAAANQAECgUIBgAAAA==.Senbit:BAAANQADCgYIBgAAAA==.Serenìty:BAAANQADCggICAAAAA==.Seresin:BAAANQAECgQIBgAAAA==.',
Sh='Shadý:BAAANQADCgYICgAAAA==.Shamanoodles:BAAANQADCggIDQABNQAECgEIAQABAAAAAA==.Shortwarrior:BAAANQADCgcIDQAAAA==.',
Si='Sidraya:BAAANQADCgQIBgAAAA==.Silent:BAAANQAECgMIAwAAAA==.Silverserqet:BAAANQADCgYICwAAAA==.',
So='Sooki:BAAANQADCgIIAgAAAA==.Soulber:BAAANQADCgQIBAAAAA==.',
St='Sternhoof:BAAANQABCgEIAQAAAA==.Stigma:BAAANQADCggIFQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.',
Sw='Swowtitbang:BAAANQADCgYICwAAAA==.',
Te='Tegbolt:BAAANQADCggIDwAAAA==.Tekko:BAAANQAECgEIAQAAAA==.',
Th='Theholymatt:BAAANQAECgMIAwAAAA==.Thendari:BAAANQAECgEIAQAAAA==.Theodus:BAAANQADCggIDwAAAA==.Therayen:BAAANQADCgYIBwAAAA==.',
Ti='Tiferis:BAAANQAECgQIBQAAAA==.',
To='Tobiquer:BAAANQAECgEIAQAAAA==.Torolf:BAAANQADCgQIBAAAAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.',
Ts='Tsonokwabain:BAAANQADCggICgAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAAANQADCggICAAAAA==.Tyranastrasz:BAAANQAECgMIAwAAAA==.Tyye:BAAANQADCggIDgAAAA==.',
['Tâ']='Tâjik:BAAANQAECgMIAwAAAA==.',
Ul='Ulquiorra:BAAANQAECgUIBQAAAA==.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQADCgQIBAAAAA==.Valgavoth:BAAANQAECgEIAQAAAA==.',
Ve='Velara:BAAANQADCgEIAQAAAA==.Velinna:BAAANQADCgQIBAABNQADCgcIEQABAAAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQADCgcIDAAAAA==.',
Vo='Voidlighter:BAAANQAECgIIAgAAAA==.Volundr:BAAANQADCggIDwAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.Vynirion:BAAANQADCgcIEQAAAA==.',
Wa='Wargtar:BAAANQADCgYIBgAAAA==.',
Wy='Wyrdhoof:BAAANQADCgYICQAAAA==.',
['Wù']='Wùsthof:BAAANQAECgEIAQAAAA==.',
Xa='Xandrios:BAAANQADCgYICQAAAA==.',
Xi='Xiae:BAAANQADCgYIBgAAAA==.',
Ya='Yasuke:BAAANQADCgUIBQAAAA==.',
Ye='Yet:BAAANQADCgIIAgAAAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAAANQAECgQIBAAAAA==.',
Za='Zaraeliana:BAAANQAECgEIAQAAAA==.Zarastraza:BAAANQADCggIDQAAAA==.',
Ze='Zephnor:BAAANQADCgYIDAAAAA==.',
Zm='Zmona:BAAANQADCggICgAAAA==.',
Zu='Zulrok:BAAANQADCggICAAAAA==.',
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
