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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-09-01',data={Ah='Ahpuch:BAAANQAECgIIAgAAAA==.',
Ai='Aidasul:BAAANQADCgYICwAAAA==.',
Al='Aldesca:BAAANQADCgYICwAAAA==.',
An='Ancile:BAAANQADCgIIAgAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgMIAwAAAA==.',
Ar='Armstrõng:BAAANQAECgEIAQAAAA==.',
As='Ashpaw:BAAANQAECgQIBQAAAA==.Aspen:BAAANQADCgUIBwAAAA==.',
At='Atcjedi:BAAANQAECgQIBAAAAA==.Atmospherewr:BAAANQADCggIDgABNQAFFAEIAQABAAAAAA==.Atmospherez:BAAANQAFFAEIAQAAAA==.',
Av='Avaniah:BAAANQAECgEIAQAAAA==.',
Az='Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQADCgYICQAAAA==.Baep:BAAANQADCgUIBQAAAA==.Bandrago:BAAANQADCgYICgAAAA==.',
Be='Beaulioh:BAAANQAECgEIAQAAAA==.Bekzarn:BAAANQADCgcIBwABNQADCggIDwABAAAAAA==.Benfrank:BAAANQAECgEIAQAAAA==.Bernthul:BAAANQADCgYICQAAAA==.Bethan:BAAANQADCggIDgAAAA==.',
Bl='Blaart:BAAANQAECgQIBwAAAA==.Blackwaters:BAAANQADCggICwAAAA==.Blax:BAAANQADCgYIDgAAAA==.Blindcow:BAAANQAECgQIBAAAAA==.Blindhugs:BAAANQAECgIIAQABNQAECgIIAgABAAAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQADCgYIBgAAAA==.',
Bo='Bodytypebig:BAAANQAECgQIBgAAAA==.Boicrystian:BAAANQADCgMIBQAAAA==.Bookitty:BAAANQADCgcICgAAAA==.Boosty:BAAANQAECgQIBAAAAA==.Bossladìe:BAAANQAECgMIBAAAAA==.',
Br='Bristle:BAAANQAECgMIAwAAAA==.Brommix:BAAANQADCgMIBgAAAA==.',
Bu='Buhbles:BAAANQAECgcIBwAAAA==.Bullshiitake:BAAANQAECgQIBQAAAA==.',
Ca='Calaglin:BAAANQAECgQIBAAAAA==.Catstack:BAAANQADCgYIBgAAAA==.',
Ce='Celesti:BAAANQAECgQIBAAAAA==.',
Ch='Choom:BAAANQADCgUICgAAAA==.Chubsy:BAAANQAECggICAAAAA==.Chuckkyd:BAAANQAECgQIBAAAAA==.',
Cl='Claugh:BAAANQAECgQIBQAAAA==.Cleb:BAAANQAECgEIAQAAAA==.Clocker:BAAANQADCgcIDAAAAA==.Clumbsykoala:BAAANQADCgYICwAAAA==.',
Co='Colton:BAAANQAFFAEIAQAAAA==.Combatcow:BAAANQAECgUIBgAAAA==.Cozmic:BAAANQAECgQIBQAAAA==.',
Cr='Crucifixd:BAAANQADCgEIAQAAAA==.Crysteris:BAAANQADCgQIBgAAAA==.',
Ct='Ctrlzr:BAAANQAECgIIAgAAAA==.',
Cu='Curandero:BAAANQAECgQIBwAAAA==.Curie:BAAANQADCgYICAABNQAECgYICQABAAAAAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dameck:BAAANQAECgMIAwAAAA==.Dasdots:BAAANQADCggIDwAAAA==.Dazzeler:BAAANQADCgcIDAAAAA==.',
De='Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAAANQAECgEIAQAAAA==.Delver:BAAANQAECgEIAQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Denathria:BAAANQAECgQIBAAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAAANQAFFAEIAQAAAA==.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.',
Do='Doak:BAAANQAECgYICQAAAA==.Doonfist:BAAANQABCgQIBQAAAA==.Dottie:BAAANQADCggIGAAAAA==.Dotz:BAAANQAECgYICgAAAA==.Douchec:BAAANQADCgIIAgAAAA==.',
Dr='Draconius:BAAANQADCgMIAwAAAA==.Dragonforce:BAAANQADCgYICwAAAA==.Dragonhaze:BAAANQADCggIDgAAAA==.Drevox:BAAANQADCggIDgAAAA==.Druiddruid:BAAANQADCgMIAwAAAA==.',
Du='Dulgar:BAAANQAECgMIAwAAAA==.Dumami:BAAANQADCgIIAgAAAA==.',
['Dë']='Dëlilah:BAAANQADCgYICAAAAA==.',
El='Elleduff:BAAANQADCggIDgAAAA==.Elysstaa:BAAANQAECgMIAwAAAA==.',
En='Entïty:BAAANQADCgcIBwAAAA==.',
Eo='Eogden:BAAANQAECgQIBAAAAA==.',
Eq='Equilibria:BAAANQADCgYICwAAAA==.',
Er='Ers:BAAANQADCgYIBgABNQADCgUICAABAAAAAA==.',
Et='Etík:BAAANQADCgYICwAAAA==.',
Ev='Evocative:BAAANQAECgcIDQAAAA==.',
Ex='Exaltso:BAAANQADCgUIBQAAAA==.',
Ey='Eyye:BAAANQADCgMIAwABNQADCggICAABAAAAAA==.',
Fa='Farns:BAAANQAFFAEIAQAAAA==.Fawndolynn:BAAANQADCgYICwAAAA==.',
Fe='Felinepriest:BAAANQAECgEIAQAAAA==.Felsoaked:BAAANQADCgMIAwAAAA==.Felstehr:BAAANQADCggIDgAAAA==.',
Fi='Fiendish:BAAANQADCggIDwAAAA==.Filligri:BAAANQAECgQIBQAAAA==.Firebäne:BAAANQAECgEIAQAAAA==.Fistnor:BAAANQADCggICAAAAA==.',
Fl='Flaminghawk:BAAANQAECgYICQAAAA==.',
Fr='Freyin:BAAANQAECgIIAgAAAA==.',
Fu='Fullclangg:BAAANQAECggIBwABNQAFFAUIBgACAHIUAA==.Fulldracarys:BAABNQAFFIEGAAICAAUJchRVAADKAQACAAUJchRVAADKAQAAAA==.Fullgabagool:BAAANQAECgYIDAABNQAFFAUIBgACAHIUAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAUIBgACAHIUAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCgcIDQAAAA==.Gaya:BAAANQADCgEIAQAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAAANQAECgUICAAAAA==.',
Gn='Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgMIAwAAAA==.',
Gr='Grimknight:BAAANQAECggIDQAAAA==.',
Gu='Guycow:BAAANQAECgYICgAAAA==.',
Ha='Hambonë:BAAANQAFFAMIBAAAAA==.Hardballs:BAAANQADCgMIAwAAAA==.Hashbrowns:BAAANQAECgMIAwAAAA==.Havdk:BAEANQAECgIIAQAAAA==.Haxxorwyn:BAAANQADCgMIAwAAAA==.Hazreil:BAAANQAECgMIAwAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgQICAAAAA==.Hecklefish:BAAANQAECgUIBwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAAANQADCggIDgAAAA==.Highdegrees:BAAANQADCgQIBAAAAA==.Hitagi:BAAANQAECgIIAgAAAA==.',
Ho='Holyblasts:BAAANQADCgUIBQAAAA==.Holyfreaks:BAAANQADCgYICAAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgEIAQABAAAAAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Hummingbird:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.Hungus:BAAANQADCggIDgAAAA==.Hurtszick:BAAANQADCgIIAgAAAA==.',
Hy='Hydrotiger:BAAANQADCgIIAgAAAA==.',
['Hä']='Härasou:BAAANQADCgIIAgAAAA==.',
Il='Illiturtle:BAAANQAECgMIAwAAAA==.',
In='Indigolemon:BAAANQAECgEIAQAAAA==.Inkenhancer:BAAANQAECgEIAQAAAA==.',
Io='Iowned:BAAANQADCgYICwAAAA==.',
Ja='Jamie:BAAANQADCgcIDAAAAA==.',
Jo='Jollyollie:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQADCgQIBAAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jô']='Jôker:BAAANQADCgcICwAAAA==.',
Ka='Kacho:BAAANQADCgUIBQAAAA==.Kaelara:BAAANQADCggICAAAAA==.Kaladin:BAAANQADCgYIBwAAAA==.Kappo:BAAANQADCgYIDAAAAA==.Kathorall:BAAANQAECgMIAwAAAA==.Kawaiihealer:BAAANQAECgQIBAAAAA==.',
Ke='Keddy:BAAANQADCgMIBAAAAA==.Kemper:BAAANQADCgcIDQAAAA==.Kerrs:BAAANQADCgQIBQAAAA==.',
Ki='Kidneypopper:BAAANQADCgEIAQABNQAECgQIBQABAAAAAA==.Kievit:BAAANQADCggIDgAAAA==.Kir:BAAANQADCggICwAAAA==.Kittana:BAAANQADCggIDQAAAA==.',
Kk='Kkelhus:BAAANQADCgUIBQAAAA==.Kkrantuq:BAAANQAECgQIBQAAAA==.',
Kl='Klarityx:BAAANQADCgIIAgAAAA==.',
Ko='Koma:BAAANQADCggICAABNQAECggIDgABAAAAAA==.Komatos:BAAANQAECggIDgAAAA==.Koronus:BAAANQADCgQIBAAAAA==.',
Ks='Ks:BAAANQADCgMIAwABNQADCgcIDwABAAAAAA==.',
['Kê']='Kênsêi:BAAANQAECgMIBAAAAA==.',
['Kô']='Kôan:BAAANQADCgYICAAAAA==.',
La='Lanathel:BAAANQADCgUIBQAAAA==.',
Le='Leafyjoe:BAAANQAECgEIAQAAAA==.Legendarybob:BAAANQADCgUIBQAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAAANQAECgQIBAAAAA==.Legö:BAAANQADCgYICAABNQAECgQIBAABAAAAAA==.',
Li='Lido:BAAANQADCggICwAAAA==.Lildeemon:BAAANQAECgUIBQAAAA==.Lilspyro:BAAANQADCggIDgAAAA==.Livathian:BAAANQAECgMIAwAAAA==.',
Lo='Lokrah:BAAANQABCgMIBAAAAA==.',
Lu='Lunavel:BAAANQAECgQIBAAAAA==.',
Ly='Lydo:BAAANQAECggIBAAAAA==.',
Ma='Magicdan:BAAANQADCgEIAQAAAA==.Magicfrank:BAAANQAECgMIAwAAAA==.Malnorr:BAAANQADCgQIBAAAAA==.Mangol:BAAANQADCggIDwAAAA==.Maryillo:BAAANQAFFAEIAQAAAA==.',
Mc='Mcmannis:BAAANQADCggICAAAAA==.Mcpoltrain:BAAANQADCgUICQAAAA==.',
Me='Mennil:BAAANQADCgYICwAAAA==.Meolater:BAAANQAECgIIAgAAAA==.Mesmerise:BAAANQADCgUICQAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Mindgoblinn:BAAANQADCgcIDAAAAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQADCgYICwAAAA==.',
Mm='Mmchocolat:BAAANQADCgIIAgAAAA==.',
Mo='Mokari:BAEANQAECgMIAwAAAA==.Moolissa:BAAANQADCggIDAAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgEIAgAAAA==.Morbidchaos:BAAANQAECggIDgAAAA==.Morkels:BAAANQAECgcICQABNQAFFAYIBgADALYbAA==.',
Mu='Muddyshark:BAAANQADCggIDgAAAA==.Mukatsuku:BAAANQADCgcICgAAAA==.',
My='Mykhawk:BAAANQADCgIIAgAAAA==.',
Na='Naeth:BAAANQAECgIIAgAAAA==.',
Ne='Neciecakes:BAAANQAECgMIAwAAAA==.Nee:BAAANQAECggIDgAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nelor:BAAANQAECgEIAQAAAA==.Nextgame:BAAANQAECgIIAgAAAA==.',
Ni='Nisona:BAAANQADCgYIDAAAAA==.Nitashal:BAAANQAECgQIBgAAAA==.',
No='Noremac:BAAANQADCgYIBwAAAA==.',
Ny='Nythariel:BAAANQADCgYICQAAAA==.',
Od='Odi:BAAANQADCgYICwAAAA==.',
Ok='Okiaat:BAAANQADCgIIAgAAAA==.',
Ol='Oliviawildè:BAAANQAECgMIAwAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQADCggIDwAAAA==.Pallyforhire:BAAANQADCgUICgAAAA==.Pantyblossom:BAAANQABCgQIBAABNQADCggIDQABAAAAAA==.',
Pe='Peaches:BAAANQADCgcIDwAAAA==.Pegasus:BAAANQAECgMIBgAAAA==.Pelito:BAAANQABCgQIAgAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQADCgUIBgABNQAECgIIAgABAAAAAA==.',
Ph='Phaeddrus:BAAANQADCgMIAwAAAA==.Phrix:BAAANQADCgUIBgABNQAECgUIBwABAAAAAA==.',
Pi='Pinecone:BAAANQAECgcIDAAAAA==.',
Pl='Ploppster:BAAANQADCggICAAAAA==.Plot:BAAANQADCgcICAAAAA==.',
Po='Poekimaw:BAAANQADCgUIBQAAAA==.Pokï:BAAANQADCgUIBQAAAA==.Polpo:BAAANQAECgYIBwAAAA==.Poppinin:BAAANQADCgYIDAAAAA==.Potaters:BAAANQADCgQIBAAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAAANQAECgIIAgAAAA==.',
Ps='Psychaos:BAAANQADCgEIAQAAAA==.Psychostorm:BAAANQADCgUIBQAAAA==.Psychritic:BAAANQADCgEIAQAAAA==.Psyence:BAAANQADCgIIAwAAAA==.',
Pu='Purge:BAAANQADCgMIAwAAAA==.Purrsnikitty:BAAANQADCggIDgAAAA==.',
Qu='Quillmane:BAAANQADCggIDgABNQAECgUIBwABAAAAAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAAANQAECgMIAwAAAA==.Ragingdeath:BAAANQADCgEIAQAAAA==.Rainakamugi:BAAANQAECgMIAwABNQAECgYIBgABAAAAAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQADCgYICwAAAA==.Ralphanir:BAAANQADCggIDgAAAA==.Raskreia:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.',
Re='Reek:BAAANQADCggIDwAAAA==.Rezmae:BAAANQADCgQIBAAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAAANQAECgYICwAAAA==.Rooty:BAAANQADCgEIAQAAAA==.',
Sa='Safetyspork:BAAANQADCggICAAAAA==.Sagë:BAAANQAECgEIAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Se='Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAAANQADCggIDQAAAA==.Sendh:BAAANQADCggIDQAAAA==.Sermet:BAAANQAECgEIAQAAAA==.Sermonn:BAAANQADCgcIBwAAAA==.Serous:BAAANQADCggIDgAAAA==.Setal:BAAANQAECgUIBwAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Shcho:BAAANQABCgEIAQAAAA==.Sheepe:BAAANQADCgcIDQAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinyscalp:BAAANQADCgEIAQAAAA==.',
Si='Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgEIAQAAAA==.',
Sl='Slabbster:BAAANQADCgYIDAAAAA==.',
Sm='Smooshednewt:BAAANQAECgcICwAAAA==.',
Sn='Sne:BAAANQADCgUICgAAAA==.',
So='Soo:BAAANQADCgEIAQAAAA==.Sophira:BAAANQAECgQIBQAAAA==.Soulfuria:BAAANQAECgcIBwAAAA==.',
Sp='Speknawz:BAAANQAECgUICQAAAA==.Spoiledangel:BAAANQADCggIDgAAAA==.Spoonhat:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Springz:BAAANQAECgUIBwAAAA==.',
St='Staggering:BAAANQADCggIDwAAAA==.Starryniight:BAAANQADCgYIBgAAAA==.Stickers:BAAANQADCgYIBgAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Supanova:BAAANQADCgcIBwAAAA==.',
Sv='Svelus:BAAANQAECgcIDQAAAA==.',
Sw='Swingin:BAAANQAECgEIAQAAAA==.',
Sy='Synaptichole:BAAANQADCgYICwAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tanurhide:BAAANQABCgIIAgAAAA==.Tartan:BAAANQAECgQIBQAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.',
Te='Techi:BAAANQADCgIIAgAAAA==.Temres:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Tendermulva:BAAANQAECgQIBAAAAA==.Terekk:BAAANQADCgUICAAAAA==.',
Th='Theod:BAAANQADCgYIBgAAAA==.Thesauce:BAAANQAECgYICgAAAA==.Thimo:BAAANQADCgEIAQAAAA==.Thrikal:BAAANQAECgMIAwAAAA==.',
To='Tomsmg:BAAANQAECgIIAwAAAA==.Toofs:BAAANQADCgUICAAAAA==.Toxifay:BAAANQADCggIDQAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAECgQICAABAAAAAA==.Treehuggles:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
Ug='Ughtismo:BAAANQADCgEIAQAAAA==.',
Us='Usagiknight:BAAANQAECgYICQAAAA==.',
Va='Valei:BAAANQADCgYICwAAAA==.',
Vi='Vinda:BAAANQAECgMIAwAAAA==.Vivixia:BAAANQAECgMIAwAAAA==.',
Vo='Voodoolock:BAAANQADCgYICAAAAA==.',
Wa='Wallo:BAAANQAECgIIAgAAAA==.Washedbolt:BAAANQADCgYIBgAAAA==.Washedpyro:BAAANQADCgYICwAAAA==.Washedzebu:BAAANQAECgQIBAAAAA==.',
We='Weeb:BAABNQAFFIEGAAIDAAYJthsCAAB0AgADAAYJthsCAAB0AgAAAA==.',
Wh='Whiterabbitt:BAAANQADCgYIBgAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQADCgQIBQAAAA==.',
Wo='Woa:BAAANQADCggIDQAAAA==.Woofwoofwoof:BAAANQADCggIEAAAAA==.',
['Wà']='Wàll:BAAANQADCgYIBgAAAA==.',
Xi='Xiolan:BAAANQADCgcIDAABNQAECgYICQABAAAAAA==.',
Ys='Yshaarj:BAAANQADCggIAgAAAA==.',
Yu='Yulok:BAAANQAFFAEIAQAAAA==.',
Za='Zaberra:BAAANQAECgIIAgABNQAECgQIBQABAAAAAA==.Zanarkand:BAAANQADCggIDwAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.',
Ze='Zexexe:BAAANQAECgYIBgABNQAFFAMIBAABAAAAAA==.',
Zi='Zibroth:BAAANQAECgEIAQAAAA==.Zieg:BAAANQADCgYICwABNQAECgEIAQABAAAAAA==.Zina:BAAANQADCgcIDQAAAA==.',
['Ýu']='Ýuuki:BAAANQAECgYICQAAAA==.',
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
