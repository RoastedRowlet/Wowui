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
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aarg:BAAANQABCgIIAgAAAA==.',
Ac='Achillguy:BAAANQADCgUIBQAAAA==.',
Ag='Agnostic:BAAANQAECggIDwAAAA==.',
Ai='Aisa:BAAANQAFFAIIAgAAAA==.Aish:BAAANQAFFAMIAwAAAA==.',
Ak='Akali:BAAANQAECggIDAAAAA==.',
Al='Aldofio:BAAANQAECgEIAQAAAA==.Alhttabe:BAAANQADCggIEAAAAA==.Alvln:BAAANQAECgcIDAAAAA==.',
An='Andyrios:BAAANQADCgYIBgAAAA==.',
Ap='Apoplectic:BAAANQADCgcIDAAAAA==.',
Ar='Aradinya:BAAANQADCggICAAAAA==.Arahat:BAAANQAECgEIAQAAAA==.Aralinya:BAAANQAECgcICwAAAA==.Aratus:BAAANQADCgcIBwAAAA==.Ardentflame:BAAANQADCgcICwAAAA==.Arsoul:BAAANQADCgIIAgAAAA==.',
As='Asperonia:BAAANQAFFAIIAgAAAA==.Astlyr:BAAANQADCgIIAgAAAA==.Astrid:BAAANQAECggIDgAAAA==.',
At='Athera:BAAANQADCgYIBgAAAA==.Atiermonk:BAAANQADCgQIBAAAAA==.',
Au='Auroral:BAAANQAECgcICwAAAA==.Ausdemonic:BAAANQADCgcIDAAAAA==.',
Av='Avell:BAAANQAECgMIBQAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azriox:BAAANQADCgUIBQAAAA==.Azzielliea:BAAANQAECgQIBgAAAA==.',
Ba='Barleybrew:BAAANQADCgIIAgAAAA==.Battletank:BAAANQADCggICwABNQAECgcIDAABAAAAAA==.',
Be='Beefchar:BAAANQADCggIDQAAAA==.Beefquake:BAAANQAECgUICAAAAA==.Beàr:BAAANQADCgYIBgAAAA==.',
Bi='Bigbadbaka:BAAANQAFFAIIAgAAAA==.Bigdecay:BAAANQAECgMIBAAAAA==.',
Bl='Blasez:BAAANQADCggICAAAAA==.Blazez:BAAANQAECgcICwAAAA==.Blazpew:BAAANQADCggICAAAAA==.Blood:BAEANQADCgYIDAAAAA==.',
Bo='Bogart:BAAANQAECgcICwAAAA==.Bomohomo:BAAANQAECgcICgAAAA==.Boogeymayne:BAAANQADCgIIAgAAAA==.Bootycallz:BAAANQABCgIIAgAAAA==.',
Br='Brawny:BAAANQADCgQIBAAAAA==.Brevrin:BAAANQAECgIIAgAAAA==.',
Bu='Bubbix:BAAANQADCggICAAAAA==.Buddhatime:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Buikia:BAAANQAFFAIIAgAAAA==.Buysfeetpics:BAAANQAECggIDwAAAA==.',
Ca='Calx:BAAANQAECgIIAgABNQAECgcIDAABAAAAAA==.Cannicus:BAAANQAFFAIIAgAAAA==.Cantheal:BAAANQADCgMIBQAAAA==.Cardinal:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Ce='Celavii:BAAANQAECgMIBAAAAA==.Celeena:BAAANQADCggIDgAAAA==.',
Ch='Chamane:BAAANQADCggIDQAAAA==.Chanengtotem:BAAANQADCgYIAgAAAA==.Chappell:BAAANQADCgcIDAAAAA==.Chii:BAAANQADCgEIAQAAAA==.Chillicheese:BAAANQADCgUIBwAAAA==.Chinnomojo:BAAANQAECgQIBAAAAA==.',
Ci='Cindermoon:BAAANQADCgEIAQAAAA==.',
Cl='Cloudhorn:BAAANQAECgEIAQAAAA==.',
Co='Colena:BAEANQAECgUIBgAAAA==.Coopsfire:BAAANQADCgQIBQAAAA==.Corbulus:BAAANQAECgIIBAAAAA==.',
Cr='Create:BAAANQADCgcIBwABNQADCggIDQABAAAAAA==.Crispyarrowz:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Crispymage:BAAANQAECgQIBwAAAA==.',
Ct='Ctierwarlock:BAAANQADCgQIBQABNQAFFAIIAgABAAAAAA==.',
Cy='Cyndi:BAAANQADCggICAAAAA==.Cynxs:BAAANQAECgEIAQABNQAECgUIBwABAAAAAA==.',
Da='Dannoh:BAAANQADCgUICAAAAA==.Darcious:BAAANQADCggIDQABNQAECgMIBAABAAAAAA==.Darkcinders:BAAANQAECgQIBAAAAA==.',
De='Deadjkcocoon:BAAANQADCgMIBAAAAA==.Deadlly:BAAANQAECgIIAgAAAA==.Deathrocks:BAAANQAECgYICQAAAA==.Demöníc:BAAANQAECgQICAAAAA==.Deplock:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Destria:BAAANQADCgQIBAAAAA==.Destwind:BAAANQAECgUICAAAAA==.',
Di='Dilo:BAAANQADCggIBwAAAA==.Divinfinity:BAAANQAECgEIAQAAAA==.',
Do='Dotdotseckz:BAAANQAECgQICAAAAA==.',
Dr='Dracdoy:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Drethalis:BAAANQADCgQIDAAAAA==.Drewstormio:BAAANQADCgcIBwABNQADCggIDQABAAAAAA==.Dryene:BAAANQADCggICgAAAA==.',
Ds='Dsdh:BAAANQAFFAIIAgAAAA==.',
Du='Dulang:BAAANQAECgQIBgAAAA==.',
Ec='Ectruby:BAAANQAECgcICwAAAA==.',
El='Elammental:BAAANQADCgYIBgAAAA==.Elertricsoup:BAAANQADCggIDQAAAA==.Elwarlocko:BAAANQAECgIIAgAAAA==.Elyndre:BAAANQAECggIDwAAAA==.',
Em='Emberis:BAAANQADCgUIBQAAAA==.',
En='Endlockz:BAAANQAECgUIBgAAAA==.',
Er='Erikk:BAAANQAFFAIIAgAAAA==.',
Es='Escher:BAAANQADCgMIBgAAAA==.Esprit:BAAANQAECgQIBQABNQAFFAIIAgABAAAAAA==.',
Fa='Faeia:BAAANQAECgYIDAABNQAFFAEIAgABAAAAAA==.Faenirel:BAAANQAECgMIBAABNQAECgIIAgABAAAAAA==.Faeya:BAAANQAFFAEIAgAAAA==.Fairyen:BAAANQAECgQIBAAAAA==.Faithful:BAAANQADCggIDwAAAA==.Famine:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.Farapanda:BAAANQADCgYICQAAAA==.Fastcharge:BAAANQADCggIDgABNQAECgcIDAABAAAAAA==.',
Fe='Feidutdut:BAAANQAECgIIAgAAAA==.Feldown:BAAANQAFFAEIAQAAAA==.',
Fi='Fibanocci:BAAANQAECgYICgAAAA==.Fierce:BAAANQAECgYICAAAAA==.Fixated:BAAANQAECgIIAwAAAA==.',
Fr='Frankadelic:BAAANQADCggIDAAAAA==.Frodolol:BAAANQAFFAEIAQAAAA==.Frostyfruit:BAAANQAECgIIAgAAAA==.',
Fu='Fufamace:BAAANQADCgIIAwAAAA==.Fufina:BAAANQADCgcIDQAAAA==.',
Fw='Fwoopie:BAAANQAECgIIAgAAAA==.Fwooplin:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Ga='Gannina:BAAANQAECgUIBQAAAA==.',
Gi='Gillemon:BAAANQADCgQIBQAAAA==.Givre:BAAANQADCgIIAgAAAA==.Gizzy:BAAANQADCggIDwAAAA==.',
Go='Goodra:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Goodwill:BAAANQADCgYIBgABNQAFFAEIAQABAAAAAA==.',
Gr='Greybeards:BAAANQADCgcICQAAAA==.Gritt:BAAANQADCgYIBgAAAA==.Gryffin:BAAANQAECgIIAgAAAA==.',
Gu='Gunnina:BAAANQADCgYIBgAAAA==.Gutsc:BAAANQAECgYICwAAAA==.Guyhulikatit:BAAANQADCggICAABNQAECggIEAABAAAAAA==.',
Ha='Hammerboltie:BAAANQADCggICgABNQAECgYICgABAAAAAA==.Hatewatching:BAAANQAECgYICAAAAA==.',
He='Healbòt:BAAANQADCgUIBQAAAA==.Hemorrhage:BAAANQAECgUICQAAAA==.Hermighty:BAAANQADCgMIAwAAAA==.Hershéy:BAAANQAECgIIAgAAAA==.',
Ho='Holasimón:BAAANQAECgEIAQAAAA==.Hothotseckz:BAAANQADCggIDgABNQAECgQICAABAAAAAA==.',
Hu='Hukk:BAAANQAECgMIAwAAAA==.',
Hy='Hypervoltage:BAAANQADCgMIAwAAAA==.Hypnos:BAAANQADCgYIDAAAAA==.',
['Hà']='Hà:BAAANQAECgMIAwAAAA==.',
Ia='Iamundecided:BAAANQADCggIDQAAAA==.Iamzzr:BAAANQAECgEIAQAAAA==.',
Ic='Icysun:BAAANQAECgEIAQAAAA==.',
Ig='Igneous:BAAANQADCgYIBgAAAA==.',
Im='Image:BAAANQADCgcIBwABNQADCggIDQABAAAAAA==.Imnotamage:BAAANQADCgMIBgAAAA==.',
Is='Isopod:BAAANQADCgIIAgAAAA==.',
Ja='Jackee:BAAANQAECgMIAwAAAA==.Jasmean:BAAANQAECgcICwAAAA==.',
Je='Jellybeanss:BAAANQAECgUIBwAAAA==.Jereu:BAAANQADCgQIBQAAAA==.',
Jo='Jodix:BAAANQADCgIIAgAAAA==.Johnevoker:BAAANQAECgUIBAABNQAECgYICAABAAAAAA==.Jombii:BAAANQAECgIIAwABNQAECgcIBwABAAAAAA==.Jordoom:BAAANQADCgcIDAAAAA==.',
Ju='Judicas:BAAANQADCgEIAQAAAA==.',
Ka='Kafrial:BAAANQADCgIIAgAAAA==.Kamazi:BAAANQAECgYIBgAAAA==.Kannina:BAAANQADCgUIBQAAAA==.Kariiyon:BAAANQADCggIDQAAAA==.Katalen:BAAANQADCgQIBQAAAA==.Kayapau:BAAANQAECgYICwAAAA==.',
Ke='Kevd:BAAANQAECgYICgABNQAFFAIIAgABAAAAAA==.Kevin:BAAANQAFFAIIAgAAAA==.Kevp:BAAANQADCggICAABNQAFFAIIAgABAAAAAA==.',
Kh='Khaii:BAAANQAECgcICwAAAA==.',
Ki='Kidevil:BAAANQADCgYIBgAAAA==.Kimmiereed:BAAANQAECgQIBwAAAA==.',
Ko='Komai:BAAANQAECgUIBgAAAA==.Kopikia:BAAANQAECgUIBwAAAA==.',
Kr='Krucify:BAAANQADCggIEAAAAA==.',
Kt='Ktx:BAAANQAECgUIBgAAAA==.',
Ku='Kulak:BAAANQADCgUIBQAAAA==.',
Ky='Kyall:BAAANQAECgQIBAAAAA==.',
La='Lamerzz:BAAANQADCgYICwAAAA==.',
Le='Lebronyames:BAAANQADCgcIBwAAAA==.Lelith:BAAANQAECgQIBAAAAA==.Lerazar:BAAANQAECgEIAQAAAA==.Lettuce:BAAANQAECgIIAwAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Liquidvoid:BAAANQAECgMIAwAAAA==.',
Lu='Luurch:BAAANQAFFAEIAQAAAA==.',
Ly='Lynnae:BAAANQADCgUIBQABNQADCgUIBQABAAAAAA==.Lythium:BAAANQADCgMIAwAAAA==.',
['Lî']='Lîght:BAAANQADCgUIBQABNQAECgMIAwABAAAAAA==.',
Ma='Maceson:BAAANQADCgYICgAAAA==.Magikcreepz:BAAANQAECggIBAAAAA==.Marvik:BAAANQADCgIIAgAAAA==.Masquerapet:BAAANQAFFAIIAgAAAA==.',
Me='Megadeath:BAAANQAECgUIBgAAAA==.Mentalas:BAAANQAECgEIAQAAAA==.Mepuzzible:BAAANQAECgUIBQAAAA==.Meulah:BAAANQADCgQIBAAAAA==.',
Mi='Miah:BAAANQAECgMIAwAAAA==.Miao:BAAANQAECggIDQABNQAFFAIIAgABAAAAAA==.Miaomiaomiao:BAAANQAFFAIIAgAAAA==.Minamai:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Misdirecting:BAAANQADCgYICgABNQADCggIDQABAAAAAA==.',
Mo='Monggoloid:BAAANQADCgMIAwAAAA==.Monsieurstun:BAAANQADCgEIAQAAAA==.Moongrass:BAAANQADCggIDQAAAA==.Mousemarâ:BAAANQAECgIIAgAAAA==.',
Mu='Mungomania:BAAANQAECgEIAQAAAA==.Mutedz:BAAANQAECggIDwAAAA==.',
Na='Nargorr:BAAANQADCgYIBgAAAA==.Naruwa:BAAANQADCgMIAwAAAA==.',
Ne='Necroticlol:BAAANQAECggIDwAAAA==.Necroticlòl:BAAANQADCggICAABNQAECggIDwABAAAAAA==.Neeyana:BAAANQADCgIIAgAAAA==.Nefpore:BAAANQADCgcIDAAAAA==.Nenepok:BAAANQADCgMIAwAAAA==.',
Ni='Niij:BAAANQADCgcIDAAAAA==.Nitox:BAAANQADCggIDQAAAA==.',
No='Nosok:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Notwiththema:BAAANQAECgIIAgAAAA==.Noughtawolf:BAAANQAECgIIAgAAAA==.',
Nt='Nthope:BAAANQAFFAIIAgAAAQ==.',
Pa='Palabean:BAAANQADCgUIBgAAAA==.',
Pe='Peeta:BAAANQADCgIIAgAAAA==.Pepperino:BAAANQADCgMIAwAAAA==.',
Pi='Piyona:BAAANQAECgIIAgAAAA==.',
Po='Poros:BAAANQADCgYIBgABNQAECgcIBwABAAAAAA==.Porosdk:BAAANQAECgcIBwAAAA==.Poteb:BAAANQADCgUIBwAAAA==.Powerangers:BAAANQADCgIIAgAAAA==.',
Pr='Prodigal:BAAANQAECgcICwAAAA==.',
Pt='Pterion:BAAANQADCgUIBQAAAA==.',
Pu='Pumbz:BAAANQAECgEIAQAAAA==.Punprepared:BAEANQAECgIIAgAAAA==.',
Qe='Qeb:BAAANQAECggIEAAAAA==.',
Qi='Qio:BAAANQABCgQIAgAAAA==.',
['Qí']='Qíqi:BAAANQAECgUIBgAAAA==.',
Ra='Rashes:BAAANQADCgEIAQAAAA==.Ratix:BAAANQADCgYIBQAAAA==.Ravenn:BAAANQADCggIDQAAAA==.Razoxaynne:BAAANQAECgEIAQAAAA==.',
Rh='Rhyker:BAAANQAECgEIAQAAAA==.',
Ri='Rimreaper:BAAANQADCgcIBwAAAA==.',
Ru='Ruptured:BAAANQAECgEIAgAAAA==.',
['Rä']='Räzoxane:BAAANQADCgIIAgAAAA==.',
Sh='Shadowboiz:BAAANQAECgUIBQAAAA==.Shamdoy:BAAANQAECgIIAwAAAA==.Shapeshiift:BAAANQADCgYIBgAAAA==.Shidann:BAAANQAFFAIIAgAAAA==.Shiifty:BAAANQADCgIIBAAAAA==.Shintopal:BAAANQADCggICAAAAA==.Shintoslash:BAAANQADCgYICgAAAA==.',
Si='Silverdeath:BAAANQAECgIIAgAAAA==.Silvermaiden:BAAANQABCgIIAgAAAA==.Sinorph:BAAANQAECgUIBgAAAA==.',
Sl='Slappuccino:BAAANQAECgEIAgAAAA==.Sleeptime:BAAANQAECgIIAgAAAA==.',
Sn='Sneakyitch:BAAANQAECgUIBAAAAA==.Snipez:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.',
So='Soil:BAAANQAECgcIDAAAAA==.Solanaz:BAAANQADCgYICAAAAA==.Somepally:BAAANQAECgQIBAABNQAECgIIAgABAAAAAA==.Sorahal:BAAANQADCgEIAQAAAA==.',
Sp='Spagalnero:BAAANQAECgEIAQAAAA==.',
St='Stampedê:BAAANQADCgYIBgAAAA==.Stan:BAAANQAFFAIIAgAAAA==.Stanstanstan:BAAANQADCggICAABNQAFFAIIAgABAAAAAA==.Stier:BAAANQADCgQIBAABNQADCggIDQABAAAAAA==.Stiggyy:BAAANQADCgYIBgAAAA==.Stiria:BAAANQAECgIIAgAAAA==.Stormscythe:BAAANQADCggIDQAAAA==.',
Su='Superdope:BAAANQADCgUIBwAAAA==.Superfly:BAAANQAECgEIAgAAAA==.Sutiao:BAAANQAECgcIDAAAAA==.',
Sw='Switchknife:BAAANQAECgIIAgAAAA==.',
Sy='Sylasiana:BAAANQADCggIDAAAAA==.Synasta:BAAANQAECgcICwAAAA==.',
Ta='Tallia:BAAANQADCgQIBQABNQAECgQICAABAAAAAA==.Talons:BAAANQAECgIIAgAAAA==.Tancs:BAAANQADCggIDQAAAA==.Tarocakes:BAAANQAECgMIAwAAAA==.Taurium:BAAANQAECgUIBgAAAA==.',
Te='Teaki:BAAANQAECgEIAgAAAA==.Telsh:BAAANQAECgIIAgAAAA==.Temsik:BAAANQAECgEIAgAAAA==.Temsikdab:BAAANQADCgEIAQAAAA==.',
Th='Thoth:BAAANQAECgYICQAAAA==.Thrallish:BAAANQADCgcIBwAAAA==.Thrux:BAAANQAECgEIAQAAAA==.',
Ti='Tidal:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Tiddlyniblit:BAAANQADCgcIDAAAAA==.',
To='Tommyh:BAAANQAFFAIIAgAAAA==.Topuzzible:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.Torress:BAAANQADCgYICgAAAA==.Totemistyk:BAAANQADCgYIDAAAAA==.Toufz:BAAANQAECgQIBQAAAA==.',
Tr='Trianth:BAAANQAECgQIBAAAAA==.Tribbie:BAAANQAECgcIDAAAAA==.',
Tw='Twidger:BAAANQADCgcIDAAAAA==.',
Ty='Tyranadia:BAAANQAECggIDwAAAA==.Tystus:BAAANQADCgYIBgAAAA==.',
Up='Upstairs:BAAANQAECgYICAAAAA==.',
Ur='Uruga:BAAANQADCgYICwAAAA==.',
Va='Varnoxx:BAAANQAECgcICwAAAA==.',
Vi='Vicioûs:BAAANQAECgQIBgAAAA==.Vishnar:BAAANQAECgcICQAAAA==.',
Vo='Vollic:BAAANQADCggICAAAAA==.',
Vv='Vvoo:BAAANQAECgEIAQAAAA==.',
Vy='Vyndish:BAAANQADCgEIAQAAAA==.',
Wa='Wander:BAAANQAECgMIAwAAAA==.Wardz:BAAANQADCgUIBQAAAA==.Wazaldin:BAAANQADCgMIAwAAAA==.',
Wh='Whispess:BAAANQADCggIDQAAAA==.',
Wo='Woodro:BAAANQAECgQIBgAAAA==.Woz:BAAANQADCgcIDAAAAA==.',
Xl='Xln:BAAANQADCgcICgABNQAECgMIAwABAAAAAA==.',
Xt='Xtion:BAAANQAECgcICwAAAA==.',
Ya='Yagnatia:BAAANQAECgUIAgAAAA==.',
Yo='Yongbok:BAAANQADCgcICwAAAA==.',
Yr='Yrano:BAAANQADCgcIDAAAAA==.',
Yv='Yva:BAAANQADCggIBAAAAA==.',
Za='Zaraxes:BAAANQADCgMIBQAAAA==.',
Ze='Zelgaira:BAAANQAECgYICgABNQAECgcICwABAAAAAA==.Zelind:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Zelvaris:BAAANQAFFAIIAgAAAA==.Zenõ:BAAANQAECgMIAgAAAA==.Zerkerman:BAAANQADCgIIAgAAAA==.',
Zi='Zirka:BAAANQAECgQICAAAAA==.',
Zu='Zucchini:BAAANQADCgYIBgAAAA==.',
Zy='Zylexo:BAAANQABCgIIAgAAAA==.',
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
